# frozen_string_literal: true

require_relative "../test_helper"

class PIIClassifierPipelineTest < Minitest::Test
  include PromptGuardTestHelper

  def new_pipeline(**opts)
    defaults = { task: "pii-classifier", model_id: "test/pii-model" }
    PromptGuard::PIIClassifierPipeline.new(**defaults.merge(opts))
  end

  # --- Initialization ---

  def test_stores_task_and_model_id
    pipeline = new_pipeline
    assert_equal "pii-classifier", pipeline.task
    assert_equal "test/pii-model", pipeline.model_id
  end

  def test_default_threshold
    pipeline = new_pipeline
    assert_equal 0.5, pipeline.threshold
  end

  # --- Sigmoid ---

  def test_sigmoid_computation
    pipeline = new_pipeline
    # sigmoid(0) = 0.5
    assert_in_delta 0.5, pipeline.send(:sigmoid, 0.0), 0.001
    # sigmoid(large positive) ~ 1.0
    assert_in_delta 1.0, pipeline.send(:sigmoid, 10.0), 0.001
    # sigmoid(large negative) ~ 0.0
    assert_in_delta 0.0, pipeline.send(:sigmoid, -10.0), 0.001
  end

  # --- Inference with stubs (multi-label: asking/giving PII) ---

  def test_call_returns_expected_hash_shape
    pipeline = new_pipeline
    pipeline.instance_variable_set(:@id2label, {
      0 => "privacy_asking_for_pii",
      1 => "privacy_giving_pii"
    })

    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2, 3])
    fake_encoding.expect(:attention_mask, [1, 1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["test text"])

    fake_session = Minitest::Mock.new
    # Low logits -> not PII
    fake_session.expect(:predict, { "logits" => [[-3.0, -4.0]] }, [Hash])

    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, fake_tokenizer)
    pipeline.instance_variable_set(:@session, fake_session)

    result = pipeline.call("test text")

    assert_kind_of Hash, result
    assert_equal "test text", result[:text]
    assert_includes [true, false], result[:is_pii]
    assert_kind_of String, result[:label]
    assert_kind_of Float, result[:score]
    assert_kind_of Hash, result[:scores]
    assert_equal 2, result[:scores].size
    assert_includes result[:scores].keys, "privacy_asking_for_pii"
    assert_includes result[:scores].keys, "privacy_giving_pii"
    assert_kind_of Float, result[:inference_time_ms]
  end

  def test_call_detects_pii_asking
    pipeline = new_pipeline(threshold: 0.5)
    pipeline.instance_variable_set(:@id2label, {
      0 => "privacy_asking_for_pii",
      1 => "privacy_giving_pii"
    })

    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2, 3])
    fake_encoding.expect(:attention_mask, [1, 1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["What is your phone number?"])

    fake_session = Minitest::Mock.new
    # High logit for asking, low for giving
    fake_session.expect(:predict, { "logits" => [[3.0, -3.0]] }, [Hash])

    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, fake_tokenizer)
    pipeline.instance_variable_set(:@session, fake_session)

    result = pipeline.call("What is your phone number?")

    assert result[:is_pii]
    assert_equal "privacy_asking_for_pii", result[:label]
    assert result[:score] > 0.9
    assert result[:scores]["privacy_asking_for_pii"] > 0.9
    assert result[:scores]["privacy_giving_pii"] < 0.1
  end

  def test_call_detects_safe_text
    pipeline = new_pipeline(threshold: 0.5)
    pipeline.instance_variable_set(:@id2label, {
      0 => "privacy_asking_for_pii",
      1 => "privacy_giving_pii"
    })

    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2, 3])
    fake_encoding.expect(:attention_mask, [1, 1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["Hello world"])

    fake_session = Minitest::Mock.new
    # Low logits for both -> not PII
    fake_session.expect(:predict, { "logits" => [[-5.0, -5.0]] }, [Hash])

    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, fake_tokenizer)
    pipeline.instance_variable_set(:@session, fake_session)

    result = pipeline.call("Hello world")

    refute result[:is_pii]
    assert result[:scores]["privacy_asking_for_pii"] < 0.1
    assert result[:scores]["privacy_giving_pii"] < 0.1
  end

  def test_call_detects_both_labels_above_threshold
    pipeline = new_pipeline(threshold: 0.5)
    pipeline.instance_variable_set(:@id2label, {
      0 => "privacy_asking_for_pii",
      1 => "privacy_giving_pii"
    })

    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2, 3])
    fake_encoding.expect(:attention_mask, [1, 1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["Give me your SSN, mine is 123-45-6789"])

    fake_session = Minitest::Mock.new
    # Both labels have high logits
    fake_session.expect(:predict, { "logits" => [[3.0, 4.0]] }, [Hash])

    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, fake_tokenizer)
    pipeline.instance_variable_set(:@session, fake_session)

    result = pipeline.call("Give me your SSN, mine is 123-45-6789")

    assert result[:is_pii]
    assert result[:scores]["privacy_asking_for_pii"] > 0.9
    assert result[:scores]["privacy_giving_pii"] > 0.9
    # Top label should be giving since logit is higher
    assert_equal "privacy_giving_pii", result[:label]
  end

  def test_call_with_generic_labels_when_no_config
    pipeline = new_pipeline
    # No @id2label set

    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2])
    fake_encoding.expect(:attention_mask, [1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["text"])

    fake_session = Minitest::Mock.new
    fake_session.expect(:predict, { "logits" => [[3.0, -1.0]] }, [Hash])

    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, fake_tokenizer)
    pipeline.instance_variable_set(:@session, fake_session)

    result = pipeline.call("text")

    assert_equal "LABEL_0", result[:label]
    assert_includes result[:scores].keys, "LABEL_0"
    assert_includes result[:scores].keys, "LABEL_1"
  end

  # --- Batch detection ---

  def test_detect_batch_returns_array
    pipeline = new_pipeline
    call_count = 0
    fake_call = lambda { |text|
      call_count += 1
      { text: text, is_pii: false, label: "LABEL_0", score: 0.1, scores: {}, inference_time_ms: 1.0 }
    }

    pipeline.stub(:call, fake_call) do
      results = pipeline.detect_batch(["a", "b"])
      assert_equal 2, results.length
      assert_equal 2, call_count
    end
  end

  # --- Config loading ---

  def test_load_reads_config_for_id2label
    Dir.mktmpdir do |dir|
      model_dir = File.join(dir, "test/pii-model")
      FileUtils.mkdir_p(model_dir)
      File.write(File.join(model_dir, "config.json"),
                 '{"id2label": {"0": "privacy_asking_for_pii", "1": "privacy_giving_pii"}}')
      File.write(File.join(model_dir, "model.onnx"), "fake")
      File.write(File.join(model_dir, "tokenizer.json"), "fake")

      pipeline = new_pipeline(cache_dir: dir)

      pipeline.send(:load_config!)

      id2label = pipeline.send(:id2label)
      assert_equal "privacy_asking_for_pii", id2label[0]
      assert_equal "privacy_giving_pii", id2label[1]
    end
  end

  # --- Callable ---

  def test_pipeline_is_callable
    pipeline = new_pipeline
    assert pipeline.respond_to?(:call)
  end

  # --- Loading errors ---

  def test_call_raises_model_not_found_when_files_missing
    pipeline = new_pipeline(local_path: "/tmp/nonexistent")

    assert_raises(PromptGuard::ModelNotFoundError) do
      pipeline.call("test")
    end
  end
end
