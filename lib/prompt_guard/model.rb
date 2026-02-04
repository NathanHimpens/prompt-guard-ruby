# frozen_string_literal: true

require "digest"
require "fileutils"
require "net/http"
require "uri"
require "json"

module PromptGuard
  # Gère le téléchargement et le cache des modèles depuis Hugging Face
  class Model
    HF_BASE_URL = "https://huggingface.co"
    
    # Fichiers nécessaires pour le tokenizer (le modèle ONNX doit être exporté séparément)
    TOKENIZER_FILES = {
      "tokenizer.json" => "tokenizer.json",
      "config.json" => "config.json",
      "special_tokens_map.json" => "special_tokens_map.json",
      "tokenizer_config.json" => "tokenizer_config.json"
    }.freeze

    attr_reader :model_id, :cache_dir, :local_path

    # @param model_id [String] ID Hugging Face ou chemin local
    # @param cache_dir [String, nil] Répertoire de cache
    # @param local_path [String, nil] Chemin vers un modèle ONNX pré-exporté
    def initialize(model_id, cache_dir: nil, local_path: nil)
      @model_id = model_id
      @cache_dir = cache_dir || default_cache_dir
      @local_path = local_path
    end

    # Chemin local du modèle
    def model_path
      # Si un chemin local est fourni, l'utiliser directement
      return @local_path if @local_path && File.exist?(File.join(@local_path, "model.onnx"))
      
      ensure_downloaded!
      local_model_dir
    end

    # Vérifie si le modèle est prêt (ONNX + tokenizer)
    def ready?
      path = @local_path || local_model_dir
      File.exist?(File.join(path, "model.onnx")) &&
        File.exist?(File.join(path, "tokenizer.json"))
    end

    # Vérifie si les fichiers tokenizer sont téléchargés
    def tokenizer_downloaded?
      TOKENIZER_FILES.keys.all? { |file| File.exist?(File.join(local_model_dir, file)) }
    end

    # Télécharge les fichiers tokenizer
    def ensure_downloaded!
      return if ready?
      
      unless tokenizer_downloaded?
        puts "Downloading tokenizer for #{model_id}..."
        download_tokenizer!
      end

      unless File.exist?(File.join(local_model_dir, "model.onnx"))
        raise Error, <<~MSG
          ONNX model not found for #{model_id}.
          
          This model needs to be exported to ONNX format first.
          
          Options:
          1. Use a pre-exported model by setting local_path:
             PromptGuard.configure(local_path: "/path/to/exported/model")
          
          2. Export the model yourself:
             pip install optimum[onnxruntime] transformers torch
             optimum-cli export onnx --model #{model_id} --task text-classification #{local_model_dir}
          
          3. Run the export script:
             python -c "
             import torch
             from transformers import AutoModelForSequenceClassification, AutoTokenizer
             model = AutoModelForSequenceClassification.from_pretrained('#{model_id}')
             tokenizer = AutoTokenizer.from_pretrained('#{model_id}')
             model.eval()
             dummy = tokenizer('test', return_tensors='pt')
             torch.onnx.export(model, (dummy['input_ids'], dummy['attention_mask']),
                              '#{local_model_dir}/model.onnx',
                              input_names=['input_ids', 'attention_mask'],
                              output_names=['logits'],
                              dynamic_axes={'input_ids': {0: 'batch', 1: 'seq'},
                                           'attention_mask': {0: 'batch', 1: 'seq'},
                                           'logits': {0: 'batch'}},
                              opset_version=17)
             "
        MSG
      end
    end

    # Force le re-téléchargement du tokenizer
    def download!
      TOKENIZER_FILES.keys.each do |file|
        path = File.join(local_model_dir, file)
        FileUtils.rm_f(path)
      end
      download_tokenizer!
    end

    private

    def default_cache_dir
      if ENV["PROMPT_GUARD_CACHE_DIR"]
        ENV["PROMPT_GUARD_CACHE_DIR"]
      elsif ENV["XDG_CACHE_HOME"]
        File.join(ENV["XDG_CACHE_HOME"], "prompt_guard")
      else
        File.join(Dir.home, ".cache", "prompt_guard")
      end
    end

    def local_model_dir
      @local_model_dir ||= File.join(cache_dir, "models", model_id.gsub("/", "--"))
    end

    def download_tokenizer!
      FileUtils.mkdir_p(local_model_dir)

      TOKENIZER_FILES.each do |local_name, remote_path|
        download_file(remote_path, File.join(local_model_dir, local_name))
      end
      
      puts "Tokenizer downloaded to #{local_model_dir}"
    end

    def download_file(remote_path, local_path)
      return if File.exist?(local_path)
      
      url = "#{HF_BASE_URL}/#{model_id}/resolve/main/#{remote_path}"
      
      puts "  Downloading #{remote_path}..."
      
      uri = URI.parse(url)
      response = fetch_with_redirects(uri)

      case response
      when Net::HTTPSuccess
        File.binwrite(local_path, response.body)
      else
        raise Error, "Failed to download #{url}: #{response.code} #{response.message}"
      end
    end

    def fetch_with_redirects(uri, limit = 5)
      raise Error, "Too many redirects" if limit == 0

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = 300  # 5 minutes pour les gros fichiers
      http.open_timeout = 30

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      case response
      when Net::HTTPRedirection
        new_uri = URI.parse(response["location"])
        # Handle relative redirects
        new_uri = URI.join(uri, new_uri) unless new_uri.host
        fetch_with_redirects(new_uri, limit - 1)
      else
        response
      end
    end
  end
end
