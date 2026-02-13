# frozen_string_literal: true

require "onnxruntime"
require "tokenizers"

module PromptGuard
  # Base class for all security pipelines.
  #
  # A pipeline wraps an ONNX model + tokenizer behind a callable interface.
  # On first use the pipeline lazily downloads model files from Hugging Face Hub
  # (unless a local_path is provided) and loads them into memory.
  #
  # Subclasses MUST implement `call` with task-specific inference logic.
  class Pipeline
    attr_reader :task, :model_id, :threshold, :model_manager

    # @param task [String] Pipeline task name (e.g. "prompt-injection")
    # @param model_id [String] Hugging Face model ID
    # @param threshold [Float] Confidence threshold for classification (default: 0.5)
    # @param cache_dir [String, nil] Cache directory for downloaded models
    # @param local_path [String, nil] Path to a pre-exported ONNX model directory
    # @param dtype [String] Model variant: "fp32" (default), "q8", "fp16", etc.
    # @param revision [String] Model revision/branch on HF Hub (default: "main")
    # @param model_file_name [String, nil] Override the ONNX filename
    # @param onnx_prefix [String, nil] Override the ONNX subdirectory
    def initialize(task:, model_id:, threshold: 0.5, cache_dir: nil, local_path: nil,
                   dtype: "fp32", revision: "main", model_file_name: nil, onnx_prefix: nil)
      @task = task
      @model_id = model_id
      @threshold = threshold
      @model_manager = Model.new(
        model_id,
        local_path: local_path,
        cache_dir: cache_dir,
        dtype: dtype,
        revision: revision,
        model_file_name: model_file_name,
        onnx_prefix: onnx_prefix
      )
      @loaded = false
    end

    # Run the pipeline on the given input. Subclasses must implement this.
    #
    # @param text [String] The text to analyze
    # @return [Hash, Array] Task-specific result
    def call(text)
      raise NotImplementedError, "#{self.class}#call must be implemented by subclass"
    end

    # Load the model into memory. Downloads files if needed (via Hub).
    # Called automatically on first detection.
    #
    # @return [void]
    # @raise [ModelNotFoundError] if model files are missing or cannot be downloaded
    def load!
      return if @loaded

      tokenizer_file = @model_manager.tokenizer_path
      onnx_file = @model_manager.onnx_path

      @tokenizer = Tokenizers::Tokenizer.from_file(tokenizer_file)
      @session = OnnxRuntime::Model.new(onnx_file)
      @loaded = true
    end

    # Unload the model from memory.
    #
    # @return [void]
    def unload!
      @tokenizer = nil
      @session = nil
      @loaded = false
    end

    # Check whether the model is loaded into memory.
    #
    # @return [Boolean]
    def loaded?
      @loaded
    end

    # Whether the required model files are available locally (no download needed).
    #
    # @return [Boolean]
    def ready?
      @loaded || @model_manager.ready?
    rescue StandardError
      false
    end

    private

    # Ensure the model is loaded before inference.
    def ensure_loaded!
      load! unless @loaded
    end

    # Compute softmax over an array of logits.
    #
    # @param logits [Array<Float>] Raw model output logits
    # @return [Array<Float>] Probability distribution
    def softmax(logits)
      max = logits.max
      exp_values = logits.map { |x| Math.exp(x - max) }
      sum = exp_values.sum
      exp_values.map { |x| x / sum }
    end
  end
end
