# frozen_string_literal: true

require_relative "../test_helper"

class PromptGuardPipelineTest < Minitest::Test
  include PromptGuardTestHelper

  def new_pipeline(**opts)
    defaults = { task: "prompt-guard", model_id: "test/prompt-guard-model" }
    PromptGuard::PromptGuardPipeline.new(**defaults.merge(opts))
  end

  # --- Initialization ---

  def test_stores_task_and_model_id
    pipeline = new_pipeline
    assert_equal "prompt-guard", pipeline.task
    assert_equal "test/prompt-guard-model", pipeline.model_id
  end

  def test_default_threshold
    pipeline = new_pipeline
    assert_equal 0.5, pipeline.threshold
  end

  # --- Inference with stubs (3 labels: BENIGN, INJECTION, JAILBREAK) ---

  def test_call_returns_expected_hash_shape
    pipeline = new_pipeline
    pipeline.instance_variable_set(:@id2label, { 0 => "BENIGN", 1 => "INJECTION", 2 => "JAILBREAK" })

    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2, 3])
    fake_encoding.expect(:attention_mask, [1, 1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["test text"])

    fake_session = Minitest::Mock.new
    # BENIGN wins
    fake_session.expect(:predict, { "logits" => [[5.0, -2.0, -3.0]] }, [Hash])

    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, fake_tokenizer)
    pipeline.instance_variable_set(:@session, fake_session)

    result = pipeline.call("test text")

    assert_kind_of Hash, result
    assert_equal "test text", result[:text]
    assert_equal "BENIGN", result[:label]
    assert_kind_of Float, result[:score]
    assert_kind_of Hash, result[:scores]
    assert_equal 3, result[:scores].size
    assert_includes result[:scores].keys, "BENIGN"
    assert_includes result[:scores].keys, "INJECTION"
    assert_includes result[:scores].keys, "JAILBREAK"
    assert_kind_of Float, result[:inference_time_ms]
  end

  def test_call_detects_jailbreak
    pipeline = new_pipeline
    pipeline.instance_variable_set(:@id2label, { 0 => "BENIGN", 1 => "INJECTION", 2 => "JAILBREAK" })

    fake_encoding = Minitest::Mock.new
    fake_encoding.expect(:ids, [1, 2, 3])
    fake_encoding.expect(:attention_mask, [1, 1, 1])

    fake_tokenizer = Minitest::Mock.new
    fake_tokenizer.expect(:encode, fake_encoding, ["DAN mode activated"])

    fake_session = Minitest::Mock.new
    # JAILBREAK wins
    fake_session.expect(:predict, { "logits" => [[-3.0, -2.0, 5.0]] }, [Hash])

    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, fake_tokenizer)
    pipeline.instance_variable_set(:@session, fake_session)

    result = pipeline.call("DAN mode activated")

    assert_equal "JAILBREAK", result[:label]
    assert result[:score] > 0.9
    assert result[:scores]["JAILBREAK"] > 0.9
    assert result[:scores]["BENIGN"] < 0.1
  end

  def test_call_with_generic_labels_when_no_config
    pipeline = new_pipeline
    # No @id2label set — should use generic labels

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
      { text: text, label: "BENIGN", score: 0.9, scores: {}, inference_time_ms: 1.0 }
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
      model_dir = File.join(dir, "test/prompt-guard-model")
      FileUtils.mkdir_p(model_dir)
      File.write(File.join(model_dir, "config.json"),
                 '{"id2label": {"0": "BENIGN", "1": "INJECTION", "2": "JAILBREAK"}}')
      File.write(File.join(model_dir, "model.onnx"), "fake")
      File.write(File.join(model_dir, "tokenizer.json"), "fake")

      pipeline = new_pipeline(cache_dir: dir)

      # Call load_config! directly since full load! requires real ONNX files
      pipeline.send(:load_config!)

      id2label = pipeline.send(:id2label)
      assert_equal "BENIGN", id2label[0]
      assert_equal "INJECTION", id2label[1]
      assert_equal "JAILBREAK", id2label[2]
    end
  end

  # --- Callable ---

  def test_pipeline_is_callable
    pipeline = new_pipeline
    assert pipeline.respond_to?(:call)
  end
end
