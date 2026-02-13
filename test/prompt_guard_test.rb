# frozen_string_literal: true

require_relative "test_helper"

class PromptGuardTest < Minitest::Test
  include PromptGuardTestHelper

  def test_version_matches_semver
    assert_match(/\A\d+\.\d+\.\d+\z/, PromptGuard::VERSION)
  end

  # --- Error class hierarchy ---

  def test_error_inherits_from_standard_error
    assert PromptGuard::Error < StandardError
  end

  def test_model_not_found_error_inherits_from_error
    assert PromptGuard::ModelNotFoundError < PromptGuard::Error
  end

  def test_download_error_inherits_from_error
    assert PromptGuard::DownloadError < PromptGuard::Error
  end

  def test_inference_error_inherits_from_error
    assert PromptGuard::InferenceError < PromptGuard::Error
  end

  # --- Global config ---

  def test_default_cache_dir
    ENV.delete("PROMPT_GUARD_CACHE_DIR")
    ENV.delete("XDG_CACHE_HOME")
    PromptGuard.cache_dir = nil

    expected = File.join(Dir.home, ".cache", "prompt_guard")
    assert_equal expected, PromptGuard.cache_dir
  end

  def test_cache_dir_setter
    PromptGuard.cache_dir = "/custom/path"
    assert_equal "/custom/path", PromptGuard.cache_dir
  end

  def test_default_remote_host
    PromptGuard.remote_host = nil
    assert_equal "https://huggingface.co", PromptGuard.remote_host
  end

  def test_remote_host_setter
    PromptGuard.remote_host = "https://my-mirror.example.com"
    assert_equal "https://my-mirror.example.com", PromptGuard.remote_host
  end

  def test_allow_remote_models_default_is_true
    PromptGuard.remove_instance_variable(:@allow_remote_models) if PromptGuard.instance_variable_defined?(:@allow_remote_models)
    original = ENV.delete("PROMPT_GUARD_OFFLINE")
    assert PromptGuard.allow_remote_models
  ensure
    ENV["PROMPT_GUARD_OFFLINE"] = original if original
  end

  def test_allow_remote_models_false_when_offline_env
    PromptGuard.remove_instance_variable(:@allow_remote_models) if PromptGuard.instance_variable_defined?(:@allow_remote_models)
    original = ENV["PROMPT_GUARD_OFFLINE"]
    ENV["PROMPT_GUARD_OFFLINE"] = "1"
    refute PromptGuard.allow_remote_models
  ensure
    if original
      ENV["PROMPT_GUARD_OFFLINE"] = original
    else
      ENV.delete("PROMPT_GUARD_OFFLINE")
    end
  end

  def test_allow_remote_models_setter
    PromptGuard.allow_remote_models = false
    refute PromptGuard.allow_remote_models
    PromptGuard.allow_remote_models = true
    assert PromptGuard.allow_remote_models
  end

  # --- Logger ---

  def test_logger_returns_a_logger_by_default
    assert_kind_of Logger, PromptGuard.logger
  end

  def test_logger_setter_overrides_logger
    custom_logger = Logger.new($stdout)
    PromptGuard.logger = custom_logger
    assert_equal custom_logger, PromptGuard.logger
  end

  # --- Pipeline factory ---

  def test_pipeline_returns_prompt_injection_pipeline
    pipeline = PromptGuard.pipeline("prompt-injection")
    assert_kind_of PromptGuard::PromptInjectionPipeline, pipeline
  end

  def test_pipeline_returns_prompt_guard_pipeline
    pipeline = PromptGuard.pipeline("prompt-guard")
    assert_kind_of PromptGuard::PromptGuardPipeline, pipeline
  end

  def test_pipeline_returns_pii_classifier_pipeline
    pipeline = PromptGuard.pipeline("pii-classifier")
    assert_kind_of PromptGuard::PIIClassifierPipeline, pipeline
  end

  def test_pipeline_raises_on_unknown_task
    assert_raises(ArgumentError) do
      PromptGuard.pipeline("unknown-task")
    end
  end

  def test_pipeline_uses_default_model
    pipeline = PromptGuard.pipeline("prompt-injection")
    assert_equal "protectai/deberta-v3-base-injection-onnx", pipeline.model_id
  end

  def test_pipeline_accepts_custom_model
    pipeline = PromptGuard.pipeline("prompt-injection", "custom/model")
    assert_equal "custom/model", pipeline.model_id
  end

  def test_pipeline_passes_options
    pipeline = PromptGuard.pipeline("prompt-injection", threshold: 0.8, dtype: "q8")
    assert_equal 0.8, pipeline.threshold
    assert_equal "model_quantized.onnx", pipeline.model_manager.send(:onnx_filename)
  end

  def test_pii_pipeline_gets_default_onnx_prefix
    pipeline = PromptGuard.pipeline("pii-classifier")
    assert_equal "onnx/model.onnx", pipeline.model_manager.send(:onnx_filename)
  end
end
