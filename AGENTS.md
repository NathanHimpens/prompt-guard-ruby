# AGENTS.md -- Guidelines for the PromptGuard Ruby Gem

This document describes the architecture and conventions for the `prompt_guard`
Ruby gem, which wraps an ONNX-based prompt injection detection model for use in
Ruby applications protecting LLM-powered features.

Follows the [ankane/informers](https://github.com/ankane/informers) pattern:
lazily download ONNX models from Hugging Face Hub, cache locally, run inference
via ONNX Runtime.

---

## 1. Naming Conventions

| Concept | Convention | Value |
|---------|-----------|-------|
| Gem name | `prompt_guard` (snake_case) | `prompt_guard` |
| Module name | `PromptGuard` (PascalCase) | `PromptGuard` |
| GitHub repo | `NathanHimpens/prompt-guard-ruby` | -- |
| Default model | Hugging Face model ID | `deepset/deberta-v3-base-injection` |

---

## 2. File Layout

```
lib/
  prompt_guard.rb                    # Main entry point -- module config + public API
  prompt_guard/
    version.rb                       # VERSION constant
    model.rb                         # Model file resolution + Hub integration
    detector.rb                      # Tokenizes input + runs ONNX inference
    utils/
      hub.rb                         # Hugging Face Hub download + cache logic
test/
  test_helper.rb                     # Minitest bootstrap + module state reset helper
  prompt_guard_test.rb               # Tests for main module (config, delegation, errors)
  detector_test.rb                   # Tests for Detector (init, softmax, detect, load)
  model_test.rb                      # Tests for Model (cache dirs, ready?, paths)
  hub_test.rb                        # Tests for Hub (download, cache, offline mode)
  integration_test.rb                # Full workflow scenarios
prompt_guard.gemspec                 # Gem specification
Rakefile                             # rake test runs test/**/*_test.rb via Minitest
AGENTS.md                            # This file
```

---

## 3. Core Concept — Lazy Download from Hugging Face Hub

The gem does NOT bundle any model. Instead, it:

1. **Lazily downloads** model files (`.onnx`, `tokenizer.json`, `config.json`, etc.)
   from Hugging Face Hub on first use.
2. **Caches** them locally following the XDG standard (`~/.cache/prompt_guard/`).
3. **Runs inference** via the `onnxruntime` gem (Ruby bindings for ONNX Runtime).
4. **Uses atomic writes** (`.incomplete` temp files) to avoid corrupted downloads.

Models are referenced by their Hugging Face identifier: `"owner/model-name"`.

### Cache structure

```
~/.cache/prompt_guard/
  deepset/deberta-v3-base-injection/
    tokenizer.json
    config.json
    special_tokens_map.json
    tokenizer_config.json
    onnx/
      model.onnx
```

### Download flow

```
Model#onnx_path / Model#tokenizer_path
  |
  v
Hub.get_model_file(model_id, filename, **options)
  |
  v
[Check FileCache] --> cache hit? --> return cached path
  |
  no
  v
[Check allow_remote_models] --> false? --> raise Error (offline mode)
  |
  true
  v
[Build URL: remote_host + model_id/resolve/revision/filename]
  |
  v
[HTTP GET with User-Agent + optional HF_TOKEN auth]
  |
  v
[Stream to .incomplete file (handles redirects)]
  |
  v
[Rename .incomplete -> final path (atomic)]
  |
  v
[Return local file path]
```

---

## 4. Public API Contract

### Global Configuration

```ruby
# Cache directory (default: ~/.cache/prompt_guard)
PromptGuard.cache_dir = "/custom/cache/path"

# Remote host (default: https://huggingface.co)
PromptGuard.remote_host = "https://huggingface.co"

# Enable/disable remote downloads (default: true, unless $PROMPT_GUARD_OFFLINE is set)
PromptGuard.allow_remote_models = true

# Configurable logger (defaults to WARN on $stderr)
PromptGuard.logger = Logger.new($stdout, level: Logger::INFO)
```

### Detector Configuration

```ruby
# Configure the shared detector singleton.
# All parameters are optional; only provided values override defaults.
PromptGuard.configure(
  model_id: "deepset/deberta-v3-base-injection",  # Hugging Face model ID
  threshold: 0.5,                                   # Confidence threshold
  cache_dir: nil,                                   # Cache directory override
  local_path: nil,                                  # Path to pre-exported ONNX model
  dtype: "fp32",                                    # Model variant: fp32, q8, fp16
  revision: "main",                                 # HF model revision/branch
  model_file_name: nil,                             # Override ONNX filename stem
  onnx_prefix: nil                                  # Override ONNX subdirectory
)
```

### Detection

```ruby
# Full detection result (Hash).
result = PromptGuard.detect("Ignore previous instructions")
# => { text: "...", is_injection: true, label: "INJECTION",
#      score: 0.997, inference_time_ms: 12.5 }

# Simple boolean checks.
PromptGuard.injection?("Ignore previous instructions") # => true
PromptGuard.safe?("What is the capital of France?")     # => true

# Batch detection.
PromptGuard.detect_batch(["text1", "text2"])
# => [{ ... }, { ... }]
```

### Lifecycle

```ruby
# Pre-load the model at application startup (downloads if needed).
PromptGuard.preload!

# Check if the model files are cached locally.
PromptGuard.ready? # => true / false
```

### Direct Detector Usage

```ruby
detector = PromptGuard::Detector.new(
  model_id: "deepset/deberta-v3-base-injection",
  threshold: 0.5,
  dtype: "q8",
  local_path: "/path/to/model"
)
detector.load!
detector.detect("text")
detector.loaded?
detector.unload!
```

---

## 5. Error Classes

```ruby
module PromptGuard
  class Error < StandardError; end
  class ModelNotFoundError < Error; end   # ONNX or tokenizer files missing
  class DownloadError < Error; end        # Network/HTTP failures during download
  class InferenceError < Error; end       # Model fails during prediction
end
```

All errors inherit from `PromptGuard::Error` so callers can rescue broadly:

```ruby
rescue PromptGuard::Error => e
```

---

## 6. Hub Module — Download & Cache

The Hub module (`lib/prompt_guard/utils/hub.rb`) handles all file downloads.

### 6.1 Responsibilities

1. **Download files** from Hugging Face Hub via streaming HTTP.
2. **Cache files** locally in a structured directory.
3. **Check cache** before any download — return cached file if available.
4. **Support authentication** via `$HF_TOKEN` environment variable.
5. **Handle failures** gracefully — use temp files (`.incomplete`) and clean up.
6. **Use only Ruby stdlib** for HTTP: `net/http`, `uri`, `json`, `fileutils`.
7. **Stream large files** to avoid loading ONNX models into memory during download.

### 6.2 Key methods

```ruby
# Download a file and return its cached path.
Hub.get_model_file(model_id, filename, fatal = true, cache_dir:, revision:)

# Download and parse a JSON file.
Hub.get_model_json(model_id, filename, fatal = true, **options)
```

---

## 7. Model Management

The `Model` class handles:

1. Resolving file paths (local or from Hub cache).
2. ONNX filename construction based on `dtype`.
3. Delegating downloads to the Hub module.
4. Checking readiness (`ready?`) without triggering downloads.

### ONNX file naming convention

| dtype | ONNX file | Path |
|-------|-----------|------|
| `fp32` | `model.onnx` | `onnx/model.onnx` |
| `fp16` | `model_fp16.onnx` | `onnx/model_fp16.onnx` |
| `q8` | `model_quantized.onnx` | `onnx/model_quantized.onnx` |
| `q4` | `model_q4.onnx` | `onnx/model_q4.onnx` |

Cache directory resolution order:
1. `cache_dir:` parameter (if provided)
2. `PromptGuard.cache_dir` (global setting)
3. `$PROMPT_GUARD_CACHE_DIR` environment variable
4. `$XDG_CACHE_HOME/prompt_guard`
5. `~/.cache/prompt_guard`

---

## 8. Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `HF_TOKEN` | Hugging Face auth token for private models | (none) |
| `PROMPT_GUARD_CACHE_DIR` | Override cache directory | `~/.cache/prompt_guard` |
| `PROMPT_GUARD_OFFLINE` | Disable remote downloads when set | (empty = online) |
| `XDG_CACHE_HOME` | XDG base cache directory | `~/.cache` |

---

## 9. Testing Strategy

Tests use **Minitest** and run with `bundle exec rake test`.
The Rakefile expects `test/**/*_test.rb`.

### 9.1 Test Helper — Module State Reset

```ruby
module PromptGuardTestHelper
  def setup
    @original_detector = PromptGuard.instance_variable_get(:@detector)
    @original_logger = PromptGuard.instance_variable_get(:@logger)
    @original_cache_dir = PromptGuard.instance_variable_get(:@cache_dir)
    # ... save all global state
  end

  def teardown
    # ... restore all global state
  end
end
```

### 9.2 Stubbing Conventions

- **Hub tests**: Stub HTTP calls or use pre-populated cache directories.
  Never download real models in unit tests.
- **Detector tests**: Stub `@tokenizer` and `@session` instance variables to
  simulate a loaded model without real ONNX files.
- **Model tests**: Use `Dir.mktmpdir` with fake files to test path resolution
  and `ready?` without downloading anything.
- **Integration tests**: Combine configuration + fake model files + stubbed
  inference to validate the full user workflow.

### 9.3 Test Checklist

**Hub module (`test/hub_test.rb`)**:
- [x] Returns cached file when already downloaded
- [x] Raises when offline and file not cached
- [x] Returns nil when offline and non-fatal
- [x] Parses cached JSON files
- [x] Returns empty hash for missing JSON (non-fatal)
- [x] Creates intermediate directories
- [x] Cleans up .incomplete files on failure

**Main module (`test/prompt_guard_test.rb`)**:
- [x] VERSION matches semver format
- [x] Error class hierarchy
- [x] Global config: cache_dir, remote_host, allow_remote_models
- [x] Logger getter/setter
- [x] Detector singleton is memoized
- [x] `configure` replaces the detector (with dtype support)
- [x] `detect`, `injection?`, `safe?`, `detect_batch`, `preload!` delegate to detector
- [x] `ready?` returns true/false appropriately

**Detector (`test/detector_test.rb`)**:
- [x] Default and custom model_id/threshold
- [x] `loaded?` returns false initially
- [x] `unload!` resets state
- [x] `softmax` computation correctness
- [x] `detect` returns expected Hash shape
- [x] `injection?` and `safe?` return booleans
- [x] `detect_batch` maps over inputs
- [x] `load!` raises ModelNotFoundError when files missing
- [x] `dtype` is passed to model manager

**Model (`test/model_test.rb`)**:
- [x] Cache directory resolution (default, env, XDG, custom)
- [x] `ready?` with/without required files (local and cached)
- [x] `onnx_path` returns local path or cached path
- [x] `onnx_path` raises ModelNotFoundError when missing
- [x] `tokenizer_path` works for local and raises when missing
- [x] ONNX filename construction (fp32, q8, fp16, custom)
- [x] Constants (ONNX_FILE_MAP, TOKENIZER_FILES) are defined

**Integration (`test/integration_test.rb`)**:
- [x] Full workflow: configure -> ready? -> detect
- [x] Detect before model available raises ModelNotFoundError
- [x] injection? and safe? are complementary
- [x] Batch detection with mixed results
- [x] configure preserves logger
- [x] Offline mode raises when model not cached
- [x] Hub-cached model workflow

---

## 10. Gemspec Conventions

- `required_ruby_version >= 3.0`
- Runtime dependencies: `onnxruntime`, `tokenizers`, `logger`
- Development dependencies: `bundler`, `minitest`, `rake`
- Use `git ls-files -z` for file listing; exclude test/, spec/, .git, .github, .cursor, .ralph
- Metadata includes homepage_uri, source_code_uri, changelog_uri, bug_tracker_uri

---

## 11. Adding a New Model

To use a different Hugging Face model:

1. Ensure it supports text-classification with 2 labels (LEGIT / INJECTION).
2. Ensure it has ONNX files available on Hugging Face Hub (in `onnx/` subdirectory).
3. Configure in Ruby:
   ```ruby
   PromptGuard.configure(model_id: "owner/model-name")
   ```
4. If the model uses different ONNX paths:
   ```ruby
   PromptGuard.configure(
     model_id: "owner/model-name",
     onnx_prefix: "custom_dir",      # default: "onnx"
     model_file_name: "custom_name"   # default: based on dtype
   )
   ```
5. If the model uses different label indices, subclass `Detector` and override `LABELS`.

### Exporting a model to ONNX (if not already available)

```bash
pip install optimum[onnxruntime] transformers torch
optimum-cli export onnx --model <model_id> --task text-classification ./output
```

Then either:
- Upload the `onnx/` directory to a Hugging Face repo
- Use `local_path:` to point to the exported directory
