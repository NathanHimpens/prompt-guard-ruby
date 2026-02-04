# frozen_string_literal: true

require "onnxruntime"
require "tokenizers"

module PromptGuard
  # Détecteur d'injection de prompts
  class Detector
    LABELS = { 0 => "LEGIT", 1 => "INJECTION" }.freeze

    attr_reader :model_id, :threshold

    # Initialise le détecteur
    #
    # @param model_id [String] ID du modèle Hugging Face (default: deepset/deberta-v3-base-injection)
    # @param threshold [Float] Seuil de confiance pour la détection (default: 0.5)
    # @param cache_dir [String, nil] Répertoire de cache pour les modèles
    # @param local_path [String, nil] Chemin vers un modèle ONNX pré-exporté
    def initialize(model_id: "deepset/deberta-v3-base-injection", threshold: 0.5, cache_dir: nil, local_path: nil)
      @model_id = model_id
      @threshold = threshold
      @local_path = local_path
      @model_manager = Model.new(model_id, cache_dir: cache_dir, local_path: local_path)
      @loaded = false
    end

    # Détecte si un prompt est une injection
    #
    # @param text [String] Le texte à analyser
    # @return [Hash] Résultat avec :is_injection, :label, :score, :inference_time_ms
    def detect(text)
      ensure_loaded!

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Tokenization
      encoding = @tokenizer.encode(text)

      # Inférence
      inputs = {
        "input_ids" => [encoding.ids],
        "attention_mask" => [encoding.attention_mask]
      }
      outputs = @session.predict(inputs)
      logits = outputs["logits"][0]

      # Calcul des probabilités
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
    end

    # Vérifie si un texte est une injection (version simple)
    #
    # @param text [String] Le texte à analyser
    # @return [Boolean] true si injection détectée
    def injection?(text)
      detect(text)[:is_injection]
    end

    # Vérifie si un texte est safe
    #
    # @param text [String] Le texte à analyser
    # @return [Boolean] true si le texte est safe
    def safe?(text)
      !injection?(text)
    end

    # Analyse plusieurs textes
    #
    # @param texts [Array<String>] Les textes à analyser
    # @return [Array<Hash>] Résultats pour chaque texte
    def detect_batch(texts)
      texts.map { |text| detect(text) }
    end

    # Charge le modèle (appelé automatiquement au premier usage)
    def load!
      return if @loaded

      model_path = @model_manager.model_path

      tokenizer_path = File.join(model_path, "tokenizer.json")
      onnx_path = File.join(model_path, "model.onnx")

      @tokenizer = Tokenizers::Tokenizer.from_file(tokenizer_path)
      @session = OnnxRuntime::Model.new(onnx_path)
      @loaded = true
    end

    # Décharge le modèle de la mémoire
    def unload!
      @tokenizer = nil
      @session = nil
      @loaded = false
    end

    # Vérifie si le modèle est chargé
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
