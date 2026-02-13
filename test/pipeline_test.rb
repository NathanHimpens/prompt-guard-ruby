# frozen_string_literal: true

require_relative "test_helper"

class PipelineTest < Minitest::Test
  include PromptGuardTestHelper

  # --- Base Pipeline ---

  def test_pipeline_is_abstract
    pipeline = PromptGuard::Pipeline.new(
      task: "test",
      model_id: "test/model"
    )
    assert_raises(NotImplementedError) { pipeline.call("text") }
  end

  def test_pipeline_stores_task_and_model_id
    pipeline = PromptGuard::Pipeline.new(
      task: "prompt-injection",
      model_id: "protectai/deberta-v3-base-injection-onnx"
    )
    assert_equal "prompt-injection", pipeline.task
    assert_equal "protectai/deberta-v3-base-injection-onnx", pipeline.model_id
  end

  def test_pipeline_default_threshold
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model")
    assert_equal 0.5, pipeline.threshold
  end

  def test_pipeline_custom_threshold
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model", threshold: 0.8)
    assert_equal 0.8, pipeline.threshold
  end

  def test_pipeline_loaded_returns_false_initially
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model")
    refute pipeline.loaded?
  end

  def test_pipeline_unload_resets_state
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model")
    pipeline.instance_variable_set(:@loaded, true)
    pipeline.instance_variable_set(:@tokenizer, "fake")
    pipeline.instance_variable_set(:@session, "fake")

    pipeline.unload!

    refute pipeline.loaded?
    assert_nil pipeline.instance_variable_get(:@tokenizer)
    assert_nil pipeline.instance_variable_get(:@session)
  end

  def test_pipeline_model_manager_is_created
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model")
    assert_kind_of PromptGuard::Model, pipeline.model_manager
  end

  def test_pipeline_ready_returns_false_when_not_loaded_and_files_missing
    pipeline = PromptGuard::Pipeline.new(
      task: "test",
      model_id: "test/model",
      local_path: "/tmp/nonexistent"
    )
    refute pipeline.ready?
  end

  def test_pipeline_ready_returns_true_when_loaded
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model")
    pipeline.instance_variable_set(:@loaded, true)
    assert pipeline.ready?
  end

  def test_pipeline_ready_returns_true_when_files_present
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "model.onnx"), "fake")
      File.write(File.join(dir, "tokenizer.json"), "fake")

      pipeline = PromptGuard::Pipeline.new(
        task: "test",
        model_id: "test/model",
        local_path: dir
      )
      assert pipeline.ready?
    end
  end

  def test_pipeline_softmax
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model")
    result = pipeline.send(:softmax, [0.0, 0.0])
    assert_in_delta 0.5, result[0], 0.001
    assert_in_delta 0.5, result[1], 0.001

    result = pipeline.send(:softmax, [10.0, 0.0])
    assert_in_delta 1.0, result[0], 0.001
    assert_in_delta 0.0, result[1], 0.001
  end

  def test_pipeline_passes_dtype_to_model_manager
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model", dtype: "q8")
    assert_equal "model_quantized.onnx", pipeline.model_manager.send(:onnx_filename)
  end

  def test_pipeline_passes_onnx_prefix_to_model_manager
    pipeline = PromptGuard::Pipeline.new(task: "test", model_id: "test/model", onnx_prefix: "onnx")
    assert_equal "onnx/model.onnx", pipeline.model_manager.send(:onnx_filename)
  end

  # --- Pipeline factory ---

  def test_pipeline_factory_returns_prompt_injection_pipeline
    pipeline = PromptGuard.pipeline("prompt-injection")
    assert_kind_of PromptGuard::PromptInjectionPipeline, pipeline
    assert_equal "prompt-injection", pipeline.task
    assert_equal "protectai/deberta-v3-base-injection-onnx", pipeline.model_id
  end

  def test_pipeline_factory_returns_prompt_guard_pipeline
    pipeline = PromptGuard.pipeline("prompt-guard")
    assert_kind_of PromptGuard::PromptGuardPipeline, pipeline
    assert_equal "prompt-guard", pipeline.task
  end

  def test_pipeline_factory_returns_pii_classifier_pipeline
    pipeline = PromptGuard.pipeline("pii-classifier")
    assert_kind_of PromptGuard::PIIClassifierPipeline, pipeline
    assert_equal "pii-classifier", pipeline.task
  end

  def test_pipeline_factory_with_custom_model
    pipeline = PromptGuard.pipeline("prompt-injection", "custom/model")
    assert_equal "custom/model", pipeline.model_id
  end

  def test_pipeline_factory_with_options
    pipeline = PromptGuard.pipeline("prompt-injection", threshold: 0.8, dtype: "q8")
    assert_equal 0.8, pipeline.threshold
    assert_equal "model_quantized.onnx", pipeline.model_manager.send(:onnx_filename)
  end

  def test_pipeline_factory_raises_on_unknown_task
    err = assert_raises(ArgumentError) do
      PromptGuard.pipeline("unknown-task")
    end
    assert_includes err.message, "Unknown task"
    assert_includes err.message, "unknown-task"
  end

  def test_supported_tasks_registry
    assert_kind_of Hash, PromptGuard::SUPPORTED_TASKS
    assert_includes PromptGuard::SUPPORTED_TASKS.keys, "prompt-injection"
    assert_includes PromptGuard::SUPPORTED_TASKS.keys, "prompt-guard"
    assert_includes PromptGuard::SUPPORTED_TASKS.keys, "pii-classifier"
  end

  def test_supported_tasks_have_pipeline_and_default
    PromptGuard::SUPPORTED_TASKS.each do |task_name, task_info|
      assert task_info[:pipeline], "#{task_name} missing :pipeline"
      assert task_info[:default], "#{task_name} missing :default"
      assert task_info[:default][:model], "#{task_name} missing :default[:model]"
    end
  end
end
