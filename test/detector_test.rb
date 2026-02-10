# frozen_string_literal: true

require_relative "test_helper"

class DetectorTest < Minitest::Test
  include PromptGuardTestHelper

  def test_default_model_id
    detector = PromptGuard::Detector.new
    assert_equal "deepset/deberta-v3-base-injection", detector.model_id
  end

  def test_default_threshold
    detector = PromptGuard::Detector.new
    assert_equal 0.5, detector.threshold
  end

  def test_custom_model_id
    detector = PromptGuard::Detector.new(model_id: "custom/model")
    assert_equal "custom/model", detector.model_id
  end

  def test_custom_threshold
    detector = PromptGuard::Detector.new(threshold: 0.8)
    assert_equal 0.8, detector.threshold
  end

  def test_model_manager_is_accessible
    detector = PromptGuard::Detector.new
    assert_kind_of PromptGuard::Model, detector.model_manager
  end

  def test_loaded_returns_false_initially
    detector = PromptGuard::Detector.new
    refute detector.loaded?
  end

  def test_unload_resets_state
    detector = PromptGuard::Detector.new
    # Simulate loaded state
    detector.instance_variable_set(:@loaded, true)
    detector.instance_variable_set(:@tokenizer, "fake")
    detector.instance_variable_set(:@session, "fake")

    detector.unload!

    refute detector.loaded?
    assert_nil detector.instance_variable_get(:@tokenizer)
    assert_nil detector.instance_variable_get(:@session)
  end

  def test_labels_constant
    assert_equal({ 0 => "LEGIT", 1 => "INJECTION" }, PromptGuard::Detector::LABELS)
  end

  def test_softmax_computation
    detector = PromptGuard::Detector.new
    # softmax([0, 0]) should give [0.5, 0.5]
    result = detector.send(:softmax, [0.0, 0.0])
    assert_in_delta 0.5, result[0], 0.001
    assert_in_delta 0.5, result[1], 0.001

    # softmax with a dominant value
    result = detector.send(:softmax, [10.0, 0.0])
    assert_in_delta 1.0, result[0], 0.001
    assert_in_delta 0.0, result[1], 0.001
  end

  def test_detect_calls_load_if_not_loaded
    detector = PromptGuard::Detector.new(local_path: "/tmp/nonexistent")

    assert_raises(PromptGuard::ModelNotFoundError) do
      detector.detect("test")
    end
  end

  def test_detect_returns_expected_hash_shape
    detector = PromptGuard::Detector.new
    # Stub internals to simulate a loaded model
    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2, 3])
    fake_encoding.expect(:attention_mask, [1, 1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["test text"])

    fake_session = Minitest::Mock.new
    fake_session.expect(:predict, { "logits" => [[-2.0, 3.0]] }, [Hash])

    detector.instance_variable_set(:@loaded, true)
    detector.instance_variable_set(:@tokenizer, fake_tokenizer)
    detector.instance_variable_set(:@session, fake_session)

    result = detector.detect("test text")

    assert_kind_of Hash, result
    assert_equal "test text", result[:text]
    assert_includes [true, false], result[:is_injection]
    assert_includes ["LEGIT", "INJECTION"], result[:label]
    assert_kind_of Float, result[:score]
    assert_kind_of Float, result[:inference_time_ms]
  end

  def test_injection_returns_boolean
    detector = PromptGuard::Detector.new
    fake_result = { is_injection: true, label: "INJECTION", score: 0.99 }
    detector.stub(:detect, fake_result) do
      assert_equal true, detector.injection?("bad text")
    end
  end

  def test_safe_returns_inverse_of_injection
    detector = PromptGuard::Detector.new
    fake_result = { is_injection: true, label: "INJECTION", score: 0.99 }
    detector.stub(:detect, fake_result) do
      assert_equal false, detector.safe?("bad text")
    end
  end

  def test_detect_batch_returns_array_of_results
    detector = PromptGuard::Detector.new
    call_count = 0
    fake_detect = lambda { |text|
      call_count += 1
      { text: text, is_injection: false, label: "LEGIT", score: 0.9 }
    }

    detector.stub(:detect, fake_detect) do
      results = detector.detect_batch(["a", "b", "c"])
      assert_equal 3, results.length
      assert_equal 3, call_count
      assert_equal "a", results[0][:text]
      assert_equal "c", results[2][:text]
    end
  end

  def test_load_raises_model_not_found_when_tokenizer_missing
    Dir.mktmpdir do |dir|
      # Create only model.onnx, not tokenizer.json
      File.write(File.join(dir, "model.onnx"), "fake")

      PromptGuard.allow_remote_models = false
      detector = PromptGuard::Detector.new(local_path: dir)

      err = assert_raises(PromptGuard::ModelNotFoundError) do
        detector.load!
      end
      assert_includes err.message, "tokenizer.json"
    end
  end

  def test_load_raises_model_not_found_when_onnx_missing
    Dir.mktmpdir do |dir|
      # Create only tokenizer.json, not model.onnx
      File.write(File.join(dir, "tokenizer.json"), "{}")

      PromptGuard.allow_remote_models = false
      detector = PromptGuard::Detector.new(local_path: dir)

      err = assert_raises(PromptGuard::ModelNotFoundError) do
        detector.load!
      end
      assert_includes err.message, "model.onnx"
    end
  end

  def test_dtype_is_passed_to_model_manager
    detector = PromptGuard::Detector.new(dtype: "q8")
    # Verify through the model manager's onnx_filename
    assert_equal "onnx/model_quantized.onnx", detector.model_manager.send(:onnx_filename)
  end
end
