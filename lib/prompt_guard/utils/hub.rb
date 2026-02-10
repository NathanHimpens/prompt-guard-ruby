# frozen_string_literal: true

require "fileutils"
require "net/http"
require "uri"
require "json"

module PromptGuard
  module Utils
    # Downloads and caches model files from Hugging Face Hub.
    #
    # Follows the ankane/informers pattern:
    # - Lazily downloads files on first use
    # - Caches locally following XDG standard
    # - Atomic writes via .incomplete temp files
    # - Supports HF_TOKEN authentication
    # - Supports offline mode via PROMPT_GUARD_OFFLINE
    module Hub
      class << self
        # Download a model file from Hugging Face Hub (or return cached path).
        #
        # @param model_id [String] Hugging Face model ID (e.g. "protectai/deberta-v3-base-injection-onnx")
        # @param filename [String] File path within the model repo (e.g. "onnx/model.onnx")
        # @param fatal [Boolean] Raise on error (true) or return nil (false)
        # @param cache_dir [String, nil] Override cache directory
        # @param revision [String] Model revision/branch (default: "main")
        # @return [String, nil] Absolute path to the cached file
        # @raise [DownloadError] if download fails and fatal is true
        # @raise [Error] if offline and file not cached and fatal is true
        def get_model_file(model_id, filename, fatal = true, cache_dir: nil, revision: "main")
          dir = cache_dir || PromptGuard.cache_dir
          cache_path = File.join(dir, model_id, filename)

          # Return cached file immediately
          return cache_path if File.exist?(cache_path)

          # Offline mode check
          unless PromptGuard.allow_remote_models
            if fatal
              raise Error, "#{filename} not found in cache for #{model_id} and remote downloads are disabled " \
                           "(set PROMPT_GUARD_OFFLINE to empty or PromptGuard.allow_remote_models = true)"
            end
            return nil
          end

          # Build remote URL and download
          url = build_url(model_id, filename, revision)
          PromptGuard.logger.info("Downloading #{filename} for #{model_id}...")
          download_to_cache(url, cache_path)

          cache_path
        rescue PromptGuard::Error
          raise if fatal
          nil
        end

        # Download and parse a JSON model file.
        #
        # @param model_id [String] Hugging Face model ID
        # @param filename [String] JSON file path within the repo
        # @param fatal [Boolean] Raise on error (true) or return empty hash (false)
        # @return [Hash]
        def get_model_json(model_id, filename, fatal = true, **options)
          path = get_model_file(model_id, filename, fatal, **options)
          return {} unless path && File.exist?(path)

          JSON.parse(File.read(path))
        end

        private

        def build_url(model_id, filename, revision)
          host = PromptGuard.remote_host.chomp("/")
          "#{host}/#{model_id}/resolve/#{revision}/#{filename}"
        end

        # Download a file to the cache with atomic write (.incomplete pattern).
        def download_to_cache(url, cache_path)
          FileUtils.mkdir_p(File.dirname(cache_path))
          temp_path = "#{cache_path}.incomplete"

          begin
            stream_download(url, temp_path)
            FileUtils.mv(temp_path, cache_path)
          rescue StandardError => e
            FileUtils.rm_f(temp_path)
            raise DownloadError, "Failed to download #{url}: #{e.message}"
          end
        end

        # Stream a file download, following redirects. Writes directly to disk
        # to handle large files (ONNX models can be hundreds of MB).
        def stream_download(url, dest_path, redirect_limit = 5)
          raise DownloadError, "Too many redirects" if redirect_limit.zero?

          uri = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.read_timeout = 600 # 10 minutes for large ONNX files
          http.open_timeout = 30

          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = "prompt_guard/#{PromptGuard::VERSION} Ruby/#{RUBY_VERSION}"

          # Hugging Face authentication
          if ENV["HF_TOKEN"]
            request["Authorization"] = "Bearer #{ENV["HF_TOKEN"]}"
          end

          http.request(request) do |response|
            case response
            when Net::HTTPRedirection
              location = response["location"]
              new_uri = URI.parse(location)
              new_uri = URI.join(uri, new_uri) unless new_uri.host
              return stream_download(new_uri.to_s, dest_path, redirect_limit - 1)
            when Net::HTTPSuccess
              write_streamed_response(response, dest_path)
            else
              raise DownloadError, "HTTP #{response.code} #{response.message} for #{url}"
            end
          end
        end

        # Write an HTTP response body to disk in chunks, logging progress
        # at ~10% intervals for large files.
        def write_streamed_response(response, dest_path)
          total = response["content-length"]&.to_i
          downloaded = 0
          last_logged_pct = -10

          File.open(dest_path, "wb") do |file|
            response.read_body do |chunk|
              file.write(chunk)
              downloaded += chunk.size

              next unless total && total > 0

              pct = (downloaded * 100.0 / total).floor
              if pct >= last_logged_pct + 10
                PromptGuard.logger.info(
                  "  #{pct}% (#{format_bytes(downloaded)} / #{format_bytes(total)})"
                )
                last_logged_pct = pct
              end
            end
          end
        end

        def format_bytes(bytes)
          if bytes >= 1024 * 1024
            "#{(bytes / 1024.0 / 1024).round(1)} MB"
          elsif bytes >= 1024
            "#{(bytes / 1024.0).round(1)} KB"
          else
            "#{bytes} B"
          end
        end
      end
    end
  end
end
