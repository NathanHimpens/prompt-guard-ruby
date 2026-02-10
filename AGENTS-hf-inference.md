# AGENTS.md — Guidelines for Hugging Face ONNX Inference Ruby Gems

This document describes the architecture and conventions for Ruby gems that provide
ML inference by downloading ONNX models from Hugging Face Hub and running them via
ONNX Runtime. Inspired by [ankane/informers](https://github.com/ankane/informers).

It is meant to be copied and adapted for each new gem of this kind.

---

## 1. Core Concept

The gem does NOT bundle any model. Instead, it:

1. **Lazily downloads** model files (`.onnx`, `config.json`, `tokenizer.json`, etc.)
   from Hugging Face Hub on first use.
2. **Caches** them locally following the XDG standard (`~/.cache/<gem_name>/`).
3. **Runs inference** via the `onnxruntime` gem (Ruby bindings for ONNX Runtime).
4. **Exposes a pipeline API** that abstracts model loading, tokenization, and
   post-processing behind a single `pipeline(task, model_id)` call.

Models are referenced by their Hugging Face identifier: `"owner/model-name"`.

---

## 2. Naming Conventions

| Concept | Convention | Example |
|---------|-----------|---------|
| Gem name | `snake_case` | `informers` |
| Module name | `PascalCase` | `Informers` |
| GitHub repo | `<owner>/<gem_name>` | `ankane/informers` |
| Model reference | HF model ID | `"sentence-transformers/all-MiniLM-L6-v2"` |

---

## 3. File Layout

```
lib/
  <gem_name>.rb                    # Main entry point — requires + module + pipeline()
  <gem_name>/
    version.rb                     # VERSION constant
    env.rb                         # Global config (cache_dir, remote_host, etc.)
    configs.rb                     # Model config loader (config.json)
    models.rb                      # Model class registry + PreTrainedModel
    tokenizers.rb                  # Tokenizer loader (tokenizer.json)
    processors.rb                  # Image/audio processors (if needed)
    pipelines.rb                   # Pipeline classes (one per task type)
    backends/
      onnx.rb                      # ONNX Runtime session wrapper
    utils/
      hub.rb                       # Hugging Face Hub download + cache logic
      core.rb                      # Shared utilities (softmax, sigmoid, etc.)
      tensor.rb                    # Tensor/array helpers
      ...                          # Other domain utils (image, audio, etc.)
test/
  test_helper.rb
  <gem_name>_test.rb
  hub_test.rb
  pipeline_test.rb
  ...
<gem_name>.gemspec
Rakefile
```

---

## 4. Public API Contract

### 4.1 Main entry point — `pipeline()`

The gem exposes a single factory method that returns a callable pipeline object:

```ruby
# Create a pipeline for a specific task, optionally with a specific model.
# When model is omitted, a default model for the task is used.
pipeline = <GemName>.pipeline(task, model_id = nil, **options)

# Execute the pipeline (callable object)
result = pipeline.(input)
```

**Options:**

| Option | Type | Description |
|--------|------|-------------|
| `dtype` | String | Model variant: `"fp32"`, `"fp16"`, `"q8"`, `"q4"`, etc. |
| `device` | String | Execution device: `"cpu"`, `"cuda"`, `"coreml"` |
| `cache_dir` | String | Override default cache directory |
| `revision` | String | Model revision/branch (default: `"main"`) |
| `model_file_name` | String | Override ONNX file path within the model repo |
| `session_options` | Hash | ONNX Runtime session options |
| `progress_callback` | Proc | Called during download with progress info |

### 4.2 Global configuration

```ruby
# Cache directory (default: ~/.cache/<gem_name>/ following XDG)
<GemName>.cache_dir = "/custom/cache/path"

# Remote host (default: "https://huggingface.co/")
<GemName>.remote_host = "https://huggingface.co/"

# URL template for model files
<GemName>.remote_path_template = "{model}/resolve/{revision}/"

# Enable/disable remote downloads (default: true, unless $<GEM>_OFFLINE is set)
<GemName>.allow_remote_models = true
```

---

## 5. Error Classes

```ruby
module <GemName>
  class Error < StandardError; end
  # Extend with domain-specific errors as needed
end
```

---

## 6. Hub Module — Download & Cache

The hub module (`lib/<gem_name>/utils/hub.rb`) is the core of the distribution
mechanism. It MUST:

### 6.1 Responsibilities

1. **Download files** from Hugging Face Hub via HTTP (stdlib `open-uri`).
2. **Cache files** locally in a structured directory.
3. **Check cache** before any download — return cached file if available.
4. **Support authentication** via `$HF_TOKEN` environment variable.
5. **Handle failures** gracefully — use temp files (`.incomplete`) and clean up.
6. **Use only Ruby stdlib** for HTTP: `open-uri`, `net/http`, `uri`, `json`, `fileutils`.

### 6.2 Cache structure

```
~/.cache/<gem_name>/
  <owner>/<model_name>/
    config.json
    tokenizer.json
    onnx/
      model_quantized.onnx
```

The cache key mirrors the Hugging Face path:
- Default revision (`main`): `<owner>/<model>/filename`
- Specific revision: `<owner>/<model>/<revision>/filename`

### 6.3 Remote URL construction

```
{remote_host}/{model}/resolve/{revision}/{filename}
```

Example:
```
https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx
```

### 6.4 FileCache class

```ruby
class FileCache
  def initialize(path)
    @path = path
  end

  # Check if file exists in cache
  def match(request)
    file_path = File.join(@path, request)
    FileResponse.new(file_path) if File.exist?(file_path)
  end

  # Write response to cache with atomic write pattern
  def put(request, response)
    output_path = File.join(@path, request)
    tmp_path = "#{output_path}.incomplete"
    FileUtils.mkdir_p(File.dirname(output_path))
    File.open(tmp_path, "wb") { |f| f.write(response.read(1024 * 1024)) until response.eof? }
    FileUtils.move(tmp_path, output_path)
  end
end
```

### 6.5 Download flow

```
get_model_file(model_id, filename, **options)
  |
  v
[Check FileCache] --> cache hit? --> return cached path
  |
  no
  v
[Build remote URL: host + path_template + filename]
  |
  v
[HTTP GET with User-Agent + optional HF_TOKEN auth header]
  |
  v
[Write to cache via FileCache.put (atomic: .incomplete -> rename)]
  |
  v
[Return local file path]
```

### 6.6 get_model_file signature

```ruby
def self.get_model_file(path_or_repo_id, filename, fatal = true, **options)
  # options: cache_dir, revision, progress_callback, local_files_only
  # Returns: absolute path to the cached file
  # Raises: Error if file not found and fatal is true
  # Returns: nil if file not found and fatal is false
end
```

### 6.7 get_model_json helper

```ruby
def self.get_model_json(model_path, file_name, fatal = true, **options)
  # Downloads a JSON file and parses it
  # Returns: parsed Hash
  # Returns: {} if file not found and fatal is false
end
```

---

## 7. Config Loader

The config loader (`lib/<gem_name>/configs.rb`) downloads and parses `config.json`
from the model repository. This file contains model metadata:

- `model_type` — used to select the correct model class (e.g. `"bert"`, `"gpt2"`)
- `id2label` — label mappings for classification models
- Architecture-specific parameters (hidden size, number of heads, etc.)

```ruby
class PretrainedConfig
  def self.from_pretrained(model_name_or_path, **options)
    data = Hub.get_model_json(model_name_or_path, "config.json", true, **options)
    new(data)
  end

  def [](key)
    @config_json[key.to_s]
  end
end
```

---

## 8. Model Loading

### 8.1 Auto-resolution pattern

Models use an `AutoModel` pattern: the `model_type` field in `config.json` is
used to look up the correct Ruby class from a mapping:

```ruby
class AutoModel < PretrainedMixin
  MODEL_CLASS_MAPPINGS = [MODEL_FOR_SEQUENCE_CLASSIFICATION_MAPPING_NAMES, ...]
end
```

Each mapping is a Hash: `{ "bert" => ["BertConfig", BertForSequenceClassification], ... }`.

The flow:

```
AutoModel.from_pretrained("owner/model")
  |
  v
[Download config.json] --> extract model_type (e.g. "bert")
  |
  v
[Look up model_type in MODEL_CLASS_MAPPINGS]
  |
  v
[Call SpecificModel.from_pretrained(...)]
  |
  v
[Download ONNX file] --> create OnnxRuntime::InferenceSession
  |
  v
[Return model instance]
```

### 8.2 ONNX file naming convention

The ONNX file path depends on the `dtype` option:

| dtype | ONNX file suffix | Example path |
|-------|-----------------|--------------|
| `fp32` | (none) | `onnx/model.onnx` |
| `fp16` | `_fp16` | `onnx/model_fp16.onnx` |
| `q8` | `_quantized` | `onnx/model_quantized.onnx` |
| `int8` | `_quantized` | `onnx/model_quantized.onnx` |
| `uint8` | `_uint8` | `onnx/model_uint8.onnx` |
| `q4` | `_q4` | `onnx/model_q4.onnx` |
| `q4f16` | `_q4f16` | `onnx/model_q4f16.onnx` |
| `bnb4` | `_bnb4` | `onnx/model_bnb4.onnx` |

Default is `q8` (quantized) for smaller download size.

### 8.3 construct_session

```ruby
def self.construct_session(model_name, file_name, **options)
  model_file = "onnx/#{file_name}#{dtype_suffix}.onnx"
  path = Hub.get_model_file(model_name, model_file, true, **options)
  OnnxRuntime::InferenceSession.new(path, **session_options)
end
```

### 8.4 Model types

Different architectures need different ONNX sessions:

| Model type | Sessions loaded |
|------------|----------------|
| EncoderOnly | `model.onnx` |
| DecoderOnly | `decoder_model_merged.onnx` + `generation_config.json` |
| Seq2Seq | `encoder_model.onnx` + `decoder_model_merged.onnx` + `generation_config.json` |
| Vision2Seq | Same as Seq2Seq |
| EncoderDecoder | `encoder_model.onnx` + `decoder_model_merged.onnx` |

---

## 9. Tokenizer Loading

Tokenizers are loaded from `tokenizer.json` using the `tokenizers` gem
(Rust-based HuggingFace tokenizers with Ruby bindings):

```ruby
class AutoTokenizer
  def self.from_pretrained(model_name_or_path, **options)
    tokenizer_json_path = Hub.get_model_file(model_name_or_path, "tokenizer.json", true, **options)
    tokenizer_config = Hub.get_model_json(model_name_or_path, "tokenizer_config.json", false, **options)
    # Build tokenizer from JSON file
    Tokenizers::Tokenizer.from_file(tokenizer_json_path)
  end
end
```

---

## 10. Pipeline System

### 10.1 Pipeline factory

The `pipeline()` method is the main entry point. It:

1. Looks up the task in `SUPPORTED_TASKS` to find the default model, model class,
   tokenizer class, and pipeline class.
2. Loads the model via `AutoModel.from_pretrained(model_id, **options)`.
3. Loads the tokenizer via `AutoTokenizer.from_pretrained(model_id, **options)`.
4. Loads the processor (for vision/audio tasks) if needed.
5. Returns a pipeline instance that is callable.

```ruby
def self.pipeline(task, model = nil, **options)
  task_info = SUPPORTED_TASKS[task]
  model ||= task_info[:default][:model]

  loaded_model = task_info[:model].from_pretrained(model, **options)
  tokenizer = task_info[:tokenizer]&.from_pretrained(model, **options)
  processor = task_info[:processor]&.from_pretrained(model, **options)

  task_info[:pipeline].new(task: task, model: loaded_model, tokenizer: tokenizer, processor: processor)
end
```

### 10.2 SUPPORTED_TASKS registry

Each supported task is registered in a hash mapping task name to its components:

```ruby
SUPPORTED_TASKS = {
  "sentiment-analysis" => {
    tokenizer: AutoTokenizer,
    pipeline: TextClassificationPipeline,
    model: AutoModelForSequenceClassification,
    default: { model: "Xenova/distilbert-base-uncased-finetuned-sst-2-english" },
    type: "text"
  },
  "embedding" => {
    tokenizer: AutoTokenizer,
    pipeline: EmbeddingPipeline,
    model: AutoModel,
    default: { model: "Xenova/all-MiniLM-L6-v2" },
    type: "text"
  },
  "reranking" => {
    tokenizer: AutoTokenizer,
    pipeline: RerankingPipeline,
    model: AutoModelForSequenceClassification,
    default: { model: "Xenova/ms-marco-MiniLM-L-6-v2" },
    type: "text"
  },
  # ... more tasks
}
```

### 10.3 Pipeline base class

```ruby
class Pipeline
  def initialize(task:, model:, tokenizer: nil, processor: nil)
    @task = task
    @model = model
    @tokenizer = tokenizer
    @processor = processor
  end

  # Subclasses implement call() with task-specific logic:
  # 1. Tokenize/preprocess the input
  # 2. Run model inference
  # 3. Post-process and return structured results
end
```

### 10.4 Common pipeline types

| Pipeline class | Task | Input | Output |
|---------------|------|-------|--------|
| `TextClassificationPipeline` | `sentiment-analysis` | String | `{ label:, score: }` |
| `TokenClassificationPipeline` | `ner` | String | `[{ entity_group:, word:, score:, start:, end: }]` |
| `QuestionAnsweringPipeline` | `question-answering` | question + context | `{ answer:, score:, start:, end: }` |
| `EmbeddingPipeline` | `embedding` | String or [String] | Array of floats (vector) |
| `RerankingPipeline` | `reranking` | query + [docs] | `[{ doc_id:, score: }]` |
| `Text2TextGenerationPipeline` | `text2text-generation` | String | `{ generated_text: }` |
| `TextGenerationPipeline` | `text-generation` | String | `{ generated_text: }` |
| `SummarizationPipeline` | `summarization` | String | `{ summary_text: }` |
| `TranslationPipeline` | `translation` | String | `{ translation_text: }` |
| `FillMaskPipeline` | `fill-mask` | String with `[MASK]` | `[{ score:, token_str:, sequence: }]` |
| `ImageClassificationPipeline` | `image-classification` | image path | `{ label:, score: }` |
| `ObjectDetectionPipeline` | `object-detection` | image path | `[{ label:, score:, box: }]` |

---

## 11. Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `HF_TOKEN` | Hugging Face auth token for private models | (none) |
| `XDG_CACHE_HOME` | Base cache directory | `~/.cache` |
| `<GEM>_OFFLINE` | Disable remote downloads when set | (empty = online) |

---

## 12. Runtime Dependencies

| Gem | Purpose |
|-----|---------|
| `onnxruntime` (~> 0.x) | ONNX model inference engine |
| `tokenizers` (~> 0.x) | HuggingFace tokenizers (Rust bindings) |

**No other runtime dependencies.** HTTP download uses Ruby stdlib (`open-uri`, `net/http`, `json`, `fileutils`).

Optional dependencies (documented, not required):
- `ruby-vips` — for image loading (vision tasks)
- `ffmpeg` — for audio loading (audio tasks)

---

## 13. Gemspec Conventions

```ruby
Gem::Specification.new do |spec|
  spec.name          = "<gem_name>"
  spec.version       = <GemName>::VERSION
  spec.summary       = "Fast transformer inference for Ruby"

  spec.required_ruby_version = ">= 3.1.0"

  spec.add_dependency "onnxruntime", "~> 0.9"
  spec.add_dependency "tokenizers",  "~> 0.5"

  spec.files = Dir.glob("lib/**/*") + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.require_paths = ["lib"]
end
```

---

## 14. Adapting for a New Gem

To create a new gem following this pattern:

1. **Define your tasks** — What pipelines will the gem support? List them with
   their default models.
2. **Copy the file layout** — Especially `utils/hub.rb` (reusable as-is),
   `env.rb`, `configs.rb`.
3. **Register models** — Create the `MODEL_CLASS_MAPPINGS` for each model type
   you want to support.
4. **Implement pipelines** — One class per task, each implementing `call()` with:
   - Input preprocessing (tokenization, image processing, etc.)
   - Model inference via ONNX Runtime
   - Output post-processing (softmax, argmax, decoding, etc.)
5. **Wire `SUPPORTED_TASKS`** — Map task names to their pipeline, model, tokenizer,
   and default model.
6. **Expose `<GemName>.pipeline(task, model)`** as the main entry point.

### Key design decisions to make:

- **Which ONNX models are compatible?** The model MUST have a `.onnx` file on HF.
  Models from `Xenova/` namespace are pre-converted and reliable.
- **Default dtype**: `q8` (quantized) is a good default — smaller downloads, fast
  inference, minimal accuracy loss for most tasks.
- **Which tasks to support?** Start minimal (e.g. embedding + reranking) and add
  tasks as needed.

---

## 15. Key Differences from WASM Binary Wrapper Pattern

| Aspect | WASM Wrapper (AGENTS.md) | HF ONNX Inference (this file) |
|--------|--------------------------|-------------------------------|
| Source | GitHub Releases (single binary) | Hugging Face Hub (multiple files) |
| Format | Single `.wasm` file | `.onnx` + `.json` config files |
| Runtime | External CLI (`wasmtime`) | In-process (`onnxruntime` gem) |
| Cache | No cache (explicit `binary_path`) | XDG cache, automatic |
| Download | Explicit (`download_to_binary_path!`) | Implicit (lazy, on first use) |
| Models | One binary per gem | Any compatible HF model |
| Dependencies | Zero (stdlib only) | `onnxruntime` + `tokenizers` |
| API style | `Module.run(*args)` (CLI-like) | `pipeline.(input)` (callable object) |

---

## 16. Testing Strategy

### 16.1 Framework

Use **Minitest** (stdlib). Tests run with `rake test`.

### 16.2 Stubbing conventions

- **Hub/download tests**: Stub HTTP calls. Never download real models in unit tests.
  Use `webmock` or stub `Hub.get_model_file` to return fixture file paths.
- **Pipeline tests**: Use small fixture ONNX models or stub the ONNX session.
- **Integration tests**: Can use a real (small) model for end-to-end validation.
  Guard with `skip "Requires network"` and a CI flag.

### 16.3 Test fixtures

Provide minimal fixture files in `test/fixtures/`:

```
test/fixtures/
  config.json          # Minimal model config
  tokenizer.json       # Minimal tokenizer
  model.onnx           # Small/dummy ONNX model (optional)
```

### 16.4 Test checklist

**Hub module:**
- [ ] Downloads file from remote when not cached
- [ ] Returns cached file when already downloaded
- [ ] Sends `HF_TOKEN` in auth header when set
- [ ] Raises when `local_files_only: true` and file not in cache
- [ ] Creates intermediate directories
- [ ] Uses atomic write (`.incomplete` + rename)
- [ ] Handles HTTP errors gracefully

**Config:**
- [ ] Parses `config.json` correctly
- [ ] Exposes `model_type`, `id2label`, and other fields

**Pipeline factory:**
- [ ] Returns correct pipeline class for each supported task
- [ ] Uses default model when none specified
- [ ] Passes options through to model/tokenizer loading

**Individual pipelines:**
- [ ] Tokenizes input correctly
- [ ] Returns expected output structure
- [ ] Handles single and batched inputs
- [ ] Handles edge cases (empty input, very long input)

**Integration:**
- [ ] Full workflow: `pipeline(task, model) -> call(input) -> structured result`
- [ ] Offline mode raises when model not cached

---

## 17. Complete Flow Diagram

```
User code:
  model = <GemName>.pipeline("embedding", "sentence-transformers/all-MiniLM-L6-v2")
  embeddings = model.("Hello world")

Internal flow:

<GemName>.pipeline(task, model_id, **options)
  │
  ├─ SUPPORTED_TASKS[task]
  │    → { pipeline: EmbeddingPipeline, model: AutoModel, tokenizer: AutoTokenizer, default: ... }
  │
  ├─ AutoConfig.from_pretrained(model_id)
  │    └─ Hub.get_model_json(model_id, "config.json")
  │         ├─ FileCache.match("sentence-transformers/all-MiniLM-L6-v2/config.json")
  │         │    → cache hit? return path
  │         └─ HTTP GET https://huggingface.co/.../config.json
  │              → write to cache → return path
  │
  ├─ AutoModel.from_pretrained(model_id)
  │    ├─ config[:model_type] → "bert" → BertModel
  │    └─ construct_session(model_id, "model")
  │         └─ Hub.get_model_file(model_id, "onnx/model_quantized.onnx")
  │              → download if needed → return path
  │              → OnnxRuntime::InferenceSession.new(path)
  │
  ├─ AutoTokenizer.from_pretrained(model_id)
  │    └─ Hub.get_model_file(model_id, "tokenizer.json")
  │         → download if needed → return path
  │         → Tokenizers::Tokenizer.from_file(path)
  │
  └─ EmbeddingPipeline.new(model:, tokenizer:)
       │
       └─ pipeline.("Hello world")
            ├─ tokenizer.("Hello world") → { input_ids:, attention_mask: }
            ├─ model.(tokenized_input) → raw ONNX output
            ├─ mean_pooling(output, attention_mask)
            ├─ normalize(pooled)
            └─ return [0.012, -0.034, 0.056, ...]  # embedding vector
```
