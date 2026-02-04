# frozen_string_literal: true

require_relative "prompt_guard/version"
require_relative "prompt_guard/model"
require_relative "prompt_guard/detector"

module PromptGuard
  class Error < StandardError; end

  class << self
    # Détecteur partagé (singleton)
    # @return [Detector]
    def detector
      @detector ||= Detector.new
    end

    # Configure le détecteur par défaut
    #
    # @param model_id [String] ID du modèle Hugging Face
    # @param threshold [Float] Seuil de confiance
    # @param cache_dir [String, nil] Répertoire de cache
    # @param local_path [String, nil] Chemin vers un modèle ONNX pré-exporté
    def configure(model_id: nil, threshold: nil, cache_dir: nil, local_path: nil)
      options = {}
      options[:model_id] = model_id if model_id
      options[:threshold] = threshold if threshold
      options[:cache_dir] = cache_dir if cache_dir
      options[:local_path] = local_path if local_path
      
      @detector = Detector.new(**options)
    end

    # Détecte si un prompt est une injection
    #
    # @param text [String] Le texte à analyser
    # @return [Hash] Résultat de la détection
    #
    # @example
    #   result = PromptGuard.detect("Ignore previous instructions")
    #   result[:is_injection]  # => true
    #   result[:score]         # => 0.997
    def detect(text)
      detector.detect(text)
    end

    # Vérifie si un texte est une injection
    #
    # @param text [String] Le texte à analyser
    # @return [Boolean]
    #
    # @example
    #   PromptGuard.injection?("Ignore previous instructions")  # => true
    #   PromptGuard.injection?("What is the capital of France?")  # => false
    def injection?(text)
      detector.injection?(text)
    end

    # Vérifie si un texte est safe
    #
    # @param text [String] Le texte à analyser
    # @return [Boolean]
    def safe?(text)
      detector.safe?(text)
    end

    # Analyse plusieurs textes
    #
    # @param texts [Array<String>] Les textes à analyser
    # @return [Array<Hash>]
    def detect_batch(texts)
      detector.detect_batch(texts)
    end

    # Pré-charge le modèle
    def preload!
      detector.load!
    end
  end
end
