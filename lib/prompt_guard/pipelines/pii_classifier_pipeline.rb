# frozen_string_literal: true

module PromptGuard
  # PII (Personally Identifiable Information) detection pipeline.
  #
  # Uses a multi-label text-classification ONNX model to detect whether text
  # contains or solicits personally identifiable information.
  #
  # The label mapping is read from the model's config.json (id2label field).
  # Uses sigmoid (not softmax) because labels are independent (multi-label).
  #
  # Default model: Roblox/roblox-pii-classifier
  # Labels: privacy_asking_for_pii, privacy_giving_pii
  #
  # @example
  #   pipeline = PromptGuard.pipeline("pii-classifier")
  #   pipeline.("What is your phone number and address?")
  #   # => { text: "...", is_pii: true, label: "privacy_asking_for_pii", score: 0.92,
  #   #      scores: { "privacy_asking_for_pii" => 0.92, "privacy_giving_pii" => 0.05 },
  #   #      inference_time_ms: 15.3 }
  class PIIClassifierPipeline < Pipeline
    # Detect PII-related content in the given text.
    #
    # @param text [String] The text to analyze
    # @return [Hash] Result with :text, :is_pii, :label, :score, :scores, :inference_time_ms
    # @raise [InferenceError] if the model fails during inference
    def call(text)
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

      # Compute per-label probabilities using sigmoid (multi-label)
      probs = logits.map { |x| sigmoid(x) }

      # Find the label with the highest probability
      max_index = probs.each_with_index.max_by { |prob, _| prob }[1]
      max_score = probs[max_index]

      # Build per-label score map
      labels = id2label
      scores = {}
      probs.each_with_index do |prob, idx|
        scores[labels[idx]] = prob.round(6)
      end

      # is_pii is true if any label exceeds the threshold
      is_pii = probs.any? { |prob| prob >= threshold }

      inference_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      {
        text: text,
        is_pii: is_pii,
        label: labels[max_index],
        score: max_score,
        scores: scores,
        inference_time_ms: (inference_time * 1000).round(2)
      }
    rescue PromptGuard::Error
      raise
    rescue StandardError => e
      raise InferenceError, "Inference failed: #{e.message}"
    end

    # Analyze multiple texts.
    #
    # @param texts [Array<String>] The texts to analyze
    # @return [Array<Hash>] Results for each text
    def detect_batch(texts)
      texts.map { |text| call(text) }
    end

    # Load the model and optionally read id2label from config.json.
    #
    # @return [void]
    def load!
      return if @loaded

      load_config!
      super
    end

    private

    # Sigmoid activation function.
    #
    # @param x [Float] Input value
    # @return [Float] Sigmoid output in (0, 1)
    def sigmoid(x)
      1.0 / (1.0 + Math.exp(-x))
    end

    # Resolve the label mapping for this model.
    # Uses config.json id2label if available, otherwise generates generic labels.
    #
    # @return [Hash<Integer, String>] Index to label mapping
    def id2label
      @id2label || Hash.new { |_, k| "LABEL_#{k}" }
    end

    # Attempt to load and parse config.json for label mapping.
    def load_config!
      config = Utils::Hub.get_model_json(
        @model_id, "config.json", false,
        cache_dir: @model_manager.instance_variable_get(:@cache_dir),
        revision: @model_manager.instance_variable_get(:@revision)
      )

      if config && config["id2label"]
        @id2label = {}
        config["id2label"].each do |idx, label|
          @id2label[idx.to_i] = label.to_s
        end
      end
    rescue StandardError
      nil
    end
  end
end
