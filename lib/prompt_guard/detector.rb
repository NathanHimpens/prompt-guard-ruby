# frozen_string_literal: true

require "onnxruntime"
require "tokenizers"

module PromptGuard
  # Prompt injection detector using ONNX inference.
  #
  # On first use the detector lazily downloads model files from Hugging Face Hub
  # (unless a local_path is provided) and loads them into memory.
  class Detector
    LABELS = { 0 => "LEGIT", 1 => "INJECTION" }.freeze

    attr_reader :model_id, :threshold, :model_manager

    # Initialize the detector.
    #
    # @param model_id [String] Hugging Face model ID (default: deepset/deberta-v3-base-injection)
    # @param threshold [Float] Confidence threshold for detection (default: 0.5)
    # @param cache_dir [String, nil] Cache directory for downloaded models
    # @param local_path [String, nil] Path to a pre-exported ONNX model directory
    # @param dtype [String] Model variant: "fp32" (default), "q8", "fp16", etc.
    # @param revision [String] Model revision/branch on HF Hub (default: "main")
    # @param model_file_name [String, nil] Override the ONNX filename
    # @param onnx_prefix [String, nil] Override the ONNX subdirectory
    def initialize(model_id: "deepset/deberta-v3-base-injection", threshold: 0.5,
                   cache_dir: nil, local_path: nil, dtype: "fp32", revision: "main",
                   model_file_name: nil, onnx_prefix: nil)
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

    # Detect whether a prompt is an injection attempt.
    #
    # @param text [String] The text to analyze
    # @return [Hash] Result with :text, :is_injection, :label, :score, :inference_time_ms
    # @raise [InferenceError] if the model fails during inference
    def detect(text)
      ensure_loaded!

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Tokenization
      encoding = @tokenizer.encode(text)

      # Inference
      inputs = {
        "input_ids" => [encoding.ids],
        "attention_mask" => [encoding.attention_mask]
      }
      outputs = @session.predict(inputs)
      logits = outputs["logits"][0]

      # Compute probabilities
      probs = softmax(logits)
      predicted_class = probs.each_with_index.max_by { |prob, _| prob }[1]
      confidence = probs[predicted_class]

      inference_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      {
        text: text,
        is_injection: predicted_class == 1 && confidence >= threshold,
        label: LABELS[predicted_class],
        score: confidence,
        inference_time_ms: (inference_time * 1000).round(2)
      }
    rescue PromptGuard::Error
      raise
    rescue StandardError => e
      raise InferenceError, "Inference failed: #{e.message}"
    end

    # Check whether a text is an injection attempt (simple boolean).
    #
    # @param text [String] The text to analyze
    # @return [Boolean] true if injection detected
    def injection?(text)
      detect(text)[:is_injection]
    end

    # Check whether a text is safe (not an injection).
    #
    # @param text [String] The text to analyze
    # @return [Boolean] true if the text is safe
    def safe?(text)
      !injection?(text)
    end

    # Analyze multiple texts.
    #
    # @param texts [Array<String>] The texts to analyze
    # @return [Array<Hash>] Results for each text
    def detect_batch(texts)
      texts.map { |text| detect(text) }
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

    private

    def ensure_loaded!
      load! unless @loaded
    end

    def softmax(logits)
      max = logits.max
      exp_values = logits.map { |x| Math.exp(x - max) }
      sum = exp_values.sum
      exp_values.map { |x| x / sum }
    end
  end
end
