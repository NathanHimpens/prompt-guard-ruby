# frozen_string_literal: true

module PromptGuard
  # Manages model file resolution and downloading from Hugging Face Hub.
  #
  # Follows the ankane/informers pattern:
  # - Lazily downloads all files (ONNX + tokenizer) from HF Hub on first use
  # - Caches locally following XDG standard
  # - Supports dtype variants (fp32, q8, fp16, etc.)
  # - Supports local_path for pre-downloaded / manually exported models
  class Model
    # Map dtype shorthand to ONNX file name suffix.
    ONNX_FILE_MAP = {
      "fp32" => "model",
      "fp16" => "model_fp16",
      "q8"   => "model_quantized",
      "int8" => "model_quantized",
      "q4"   => "model_q4",
      "q4f16" => "model_q4f16"
    }.freeze

    # Subdirectory within the HF repo that contains the ONNX file.
    DEFAULT_ONNX_PREFIX = "onnx"

    # Files downloaded alongside the model for tokenization and config.
    TOKENIZER_FILES = %w[
      tokenizer.json
      config.json
      special_tokens_map.json
      tokenizer_config.json
    ].freeze

    attr_reader :model_id, :local_path

    # @param model_id [String] Hugging Face model ID (e.g. "deepset/deberta-v3-base-injection")
    # @param local_path [String, nil] Path to a local directory with pre-exported model files
    # @param cache_dir [String, nil] Override default cache directory
    # @param dtype [String] Model variant: "fp32" (default), "q8", "fp16", etc.
    # @param revision [String] Model revision/branch on HF Hub (default: "main")
    # @param model_file_name [String, nil] Override the ONNX filename (without .onnx extension)
    # @param onnx_prefix [String, nil] Override the ONNX subdirectory (default: "onnx")
    def initialize(model_id, local_path: nil, cache_dir: nil, dtype: "fp32",
                   revision: "main", model_file_name: nil, onnx_prefix: nil)
      @model_id = model_id
      @local_path = local_path
      @cache_dir = cache_dir
      @dtype = dtype
      @revision = revision
      @model_file_name = model_file_name
      @onnx_prefix = onnx_prefix
    end

    # Path to the ONNX model file. Downloads from HF Hub if needed.
    #
    # @return [String] Absolute path to model.onnx
    # @raise [ModelNotFoundError] if using local_path and file is missing
    # @raise [DownloadError] if download from HF Hub fails
    def onnx_path
      if @local_path
        local_file!("model.onnx")
      else
        Utils::Hub.get_model_file(@model_id, onnx_filename, true, **hub_options)
      end
    end

    # Path to the tokenizer.json file. Downloads from HF Hub if needed.
    #
    # @return [String] Absolute path to tokenizer.json
    # @raise [ModelNotFoundError] if using local_path and file is missing
    # @raise [DownloadError] if download from HF Hub fails
    def tokenizer_path
      if @local_path
        local_file!("tokenizer.json")
      else
        Utils::Hub.get_model_file(@model_id, "tokenizer.json", true, **hub_options)
      end
    end

    # Whether the required model files are available locally (no download needed).
    #
    # @return [Boolean]
    def ready?
      if @local_path
        File.exist?(File.join(@local_path, "model.onnx")) &&
          File.exist?(File.join(@local_path, "tokenizer.json"))
      else
        dir = @cache_dir || PromptGuard.cache_dir
        File.exist?(File.join(dir, @model_id, onnx_filename)) &&
          File.exist?(File.join(dir, @model_id, "tokenizer.json"))
      end
    end

    # Pre-download all model files (ONNX + tokenizer + config).
    # Useful to call at application startup so first inference is fast.
    #
    # @return [void]
    def preload!
      if @local_path
        local_file!("model.onnx")
        local_file!("tokenizer.json")
      else
        # Download tokenizer/config files (non-fatal -- some may not exist)
        TOKENIZER_FILES.each do |file|
          Utils::Hub.get_model_file(@model_id, file, false, **hub_options)
        end
        # Download ONNX model (fatal)
        onnx_path
      end
    end

    private

    # Build the ONNX filename based on dtype and prefix.
    # e.g. "onnx/model.onnx", "onnx/model_quantized.onnx"
    def onnx_filename
      prefix = @onnx_prefix || DEFAULT_ONNX_PREFIX
      stem = @model_file_name || ONNX_FILE_MAP.fetch(@dtype, "model")
      "#{prefix}/#{stem}.onnx"
    end

    # Options forwarded to Hub.get_model_file.
    def hub_options
      opts = {}
      opts[:cache_dir] = @cache_dir if @cache_dir
      opts[:revision] = @revision
      opts
    end

    # Resolve a file within the local_path directory.
    #
    # @raise [ModelNotFoundError] if the file does not exist
    def local_file!(filename)
      path = File.join(@local_path, filename)
      unless File.exist?(path)
        raise ModelNotFoundError, "#{filename} not found at #{path}"
      end
      path
    end
  end
end
