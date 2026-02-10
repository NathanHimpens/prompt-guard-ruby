# frozen_string_literal: true

require "logger"
require_relative "prompt_guard/version"
require_relative "prompt_guard/utils/hub"
require_relative "prompt_guard/model"
require_relative "prompt_guard/detector"

module PromptGuard
  class Error < StandardError; end
  class ModelNotFoundError < Error; end
  class DownloadError < Error; end
  class InferenceError < Error; end

  class << self
    attr_writer :logger

    # ---------------------------------------------------------------------------
    # Global configuration (ankane pattern)
    # ---------------------------------------------------------------------------

    # Cache directory for downloaded model files.
    # Resolution order: setter > $PROMPT_GUARD_CACHE_DIR > $XDG_CACHE_HOME/prompt_guard > ~/.cache/prompt_guard
    #
    # @return [String]
    def cache_dir
      @cache_dir || ENV["PROMPT_GUARD_CACHE_DIR"] ||
        (ENV["XDG_CACHE_HOME"] ? File.join(ENV["XDG_CACHE_HOME"], "prompt_guard") : nil) ||
        File.join(Dir.home, ".cache", "prompt_guard")
    end

    # Override the default cache directory.
    #
    # @param dir [String]
    attr_writer :cache_dir

    # Remote host for model downloads (default: Hugging Face Hub).
    #
    # @return [String]
    def remote_host
      @remote_host || "https://huggingface.co"
    end

    # Override the remote host (e.g. for a private mirror).
    #
    # @param host [String]
    attr_writer :remote_host

    # Whether remote model downloads are allowed.
    # Defaults to true unless $PROMPT_GUARD_OFFLINE is set.
    #
    # @return [Boolean]
    def allow_remote_models
      if instance_variable_defined?(:@allow_remote_models)
        @allow_remote_models
      else
        !ENV.key?("PROMPT_GUARD_OFFLINE")
      end
    end

    # Enable or disable remote model downloads.
    #
    # @param value [Boolean]
    attr_writer :allow_remote_models

    # ---------------------------------------------------------------------------
    # Logger
    # ---------------------------------------------------------------------------

    # Logger used for progress and diagnostic messages.
    # Defaults to a WARN-level logger on $stderr.
    #
    # @return [Logger]
    def logger
      @logger ||= Logger.new($stderr, level: Logger::WARN)
    end

    # ---------------------------------------------------------------------------
    # Detector singleton
    # ---------------------------------------------------------------------------

    # Shared detector singleton (lazily initialized).
    #
    # @return [Detector]
    def detector
      @detector ||= Detector.new
    end

    # Configure the default detector.
    #
    # Accepts all Detector options. Replaces the existing singleton.
    #
    # @param model_id [String] Hugging Face model ID
    # @param threshold [Float] Confidence threshold
    # @param cache_dir [String, nil] Cache directory for this detector
    # @param local_path [String, nil] Path to a pre-exported ONNX model
    # @param dtype [String] Model variant: "fp32", "q8", "fp16", etc.
    # @param revision [String] Model revision/branch (default: "main")
    # @param model_file_name [String, nil] Override ONNX filename
    # @param onnx_prefix [String, nil] Override ONNX subdirectory
    # @return [Detector]
    def configure(model_id: nil, threshold: nil, cache_dir: nil, local_path: nil,
                  dtype: nil, revision: nil, model_file_name: nil, onnx_prefix: nil)
      options = {}
      options[:model_id] = model_id if model_id
      options[:threshold] = threshold if threshold
      options[:cache_dir] = cache_dir if cache_dir
      options[:local_path] = local_path if local_path
      options[:dtype] = dtype if dtype
      options[:revision] = revision if revision
      options[:model_file_name] = model_file_name if model_file_name
      options[:onnx_prefix] = onnx_prefix if onnx_prefix

      @detector = Detector.new(**options)
    end

    # ---------------------------------------------------------------------------
    # Detection API (delegates to detector singleton)
    # ---------------------------------------------------------------------------

    # Detect whether a prompt is an injection attempt.
    #
    # @param text [String] The text to analyze
    # @return [Hash] Detection result
    def detect(text)
      detector.detect(text)
    end

    # Check whether a text is an injection attempt.
    #
    # @param text [String] The text to analyze
    # @return [Boolean]
    def injection?(text)
      detector.injection?(text)
    end

    # Check whether a text is safe (not an injection).
    #
    # @param text [String] The text to analyze
    # @return [Boolean]
    def safe?(text)
      detector.safe?(text)
    end

    # Analyze multiple texts.
    #
    # @param texts [Array<String>] The texts to analyze
    # @return [Array<Hash>]
    def detect_batch(texts)
      detector.detect_batch(texts)
    end

    # Pre-load the model into memory (downloads from HF Hub if needed).
    #
    # @return [void]
    def preload!
      detector.load!
    end

    # Check whether the model files are present and the detector is ready.
    #
    # @return [Boolean]
    def ready?
      detector.loaded? || detector.model_manager.ready?
    rescue StandardError
      false
    end
  end
end
