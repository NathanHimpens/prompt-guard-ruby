# frozen_string_literal: true

require "logger"
require_relative "prompt_guard/version"
require_relative "prompt_guard/utils/hub"
require_relative "prompt_guard/model"
require_relative "prompt_guard/pipelines"

module PromptGuard
  class Error < StandardError; end
  class ModelNotFoundError < Error; end
  class DownloadError < Error; end
  class InferenceError < Error; end

  class << self
    attr_writer :logger

    # ---------------------------------------------------------------------------
    # Global configuration
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
    # Pipeline factory (defined in lib/prompt_guard/pipelines.rb)
    # ---------------------------------------------------------------------------
  end
end
