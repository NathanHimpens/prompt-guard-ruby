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

  # --- Detector singleton ---

  def test_detector_returns_a_detector
    assert_kind_of PromptGuard::Detector, PromptGuard.detector
  end

  def test_detector_is_memoized
    assert_same PromptGuard.detector, PromptGuard.detector
  end

  def test_configure_replaces_detector
    old_detector = PromptGuard.detector
    PromptGuard.configure(threshold: 0.8)
    refute_same old_detector, PromptGuard.detector
    assert_equal 0.8, PromptGuard.detector.threshold
  end

  def test_configure_with_model_id
    PromptGuard.configure(model_id: "custom/model")
    assert_equal "custom/model", PromptGuard.detector.model_id
  end

  def test_configure_with_dtype
    PromptGuard.configure(dtype: "q8")
    assert_equal "model_quantized.onnx", PromptGuard.detector.model_manager.send(:onnx_filename)
  end

  # --- Delegation ---

  def test_detect_delegates_to_detector
    mock_result = { is_injection: false, label: "LEGIT", score: 0.99 }
    mock_detector = Minitest::Mock.new
    mock_detector.expect(:detect, mock_result, ["hello"])

    PromptGuard.instance_variable_set(:@detector, mock_detector)
    result = PromptGuard.detect("hello")

    assert_equal mock_result, result
    mock_detector.verify
  end

  def test_injection_delegates_to_detector
    mock_detector = Minitest::Mock.new
    mock_detector.expect(:injection?, true, ["bad input"])

    PromptGuard.instance_variable_set(:@detector, mock_detector)
    result = PromptGuard.injection?("bad input")

    assert_equal true, result
    mock_detector.verify
  end

  def test_safe_delegates_to_detector
    mock_detector = Minitest::Mock.new
    mock_detector.expect(:safe?, true, ["good input"])

    PromptGuard.instance_variable_set(:@detector, mock_detector)
    result = PromptGuard.safe?("good input")

    assert_equal true, result
    mock_detector.verify
  end

  def test_detect_batch_delegates_to_detector
    texts = ["a", "b"]
    mock_results = [{ label: "LEGIT" }, { label: "INJECTION" }]
    mock_detector = Minitest::Mock.new
    mock_detector.expect(:detect_batch, mock_results, [texts])

    PromptGuard.instance_variable_set(:@detector, mock_detector)
    result = PromptGuard.detect_batch(texts)

    assert_equal mock_results, result
    mock_detector.verify
  end

  def test_preload_delegates_to_detector
    mock_detector = Minitest::Mock.new
    mock_detector.expect(:load!, nil)

    PromptGuard.instance_variable_set(:@detector, mock_detector)
    PromptGuard.preload!

    mock_detector.verify
  end

  # --- Introspection ---

  def test_ready_returns_false_when_model_not_present
    PromptGuard.configure(local_path: "/tmp/nonexistent_model_dir")
    refute PromptGuard.ready?
  end

  def test_ready_returns_true_when_model_is_loaded
    mock_detector = Minitest::Mock.new
    mock_detector.expect(:loaded?, true)

    PromptGuard.instance_variable_set(:@detector, mock_detector)
    assert PromptGuard.ready?
    mock_detector.verify
  end
end
