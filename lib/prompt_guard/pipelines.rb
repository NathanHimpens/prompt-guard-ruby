# frozen_string_literal: true

require_relative "pipeline"
require_relative "pipelines/prompt_injection_pipeline"
require_relative "pipelines/prompt_guard_pipeline"
require_relative "pipelines/pii_classifier_pipeline"

module PromptGuard
  # Registry of supported security pipeline tasks.
  #
  # Each entry maps a task name to its pipeline class and default model.
  # Models will be downloaded from Hugging Face Hub on first use.
  SUPPORTED_TASKS = {
    "prompt-injection" => {
      pipeline: PromptInjectionPipeline,
      default: {
        model: "protectai/deberta-v3-base-injection-onnx"
      }
    },
    "prompt-guard" => {
      pipeline: PromptGuardPipeline,
      default: {
        model: "gravitee-io/Llama-Prompt-Guard-2-22M-onnx"
      }
    },
    "pii-classifier" => {
      pipeline: PIIClassifierPipeline,
      default: {
        model: "Roblox/roblox-pii-classifier",
        onnx_prefix: "onnx"
      }
    }
  }.freeze

  class << self
    # Create a pipeline for a security task.
    #
    # When model_id is omitted, uses the default model for the task.
    #
    # @param task [String] Task name (e.g. "prompt-injection", "prompt-guard", "pii-classifier")
    # @param model_id [String, nil] Hugging Face model ID (optional, uses default if nil)
    # @param threshold [Float] Confidence threshold (default: 0.5)
    # @param dtype [String] Model variant: "fp32", "q8", "fp16", etc.
    # @param cache_dir [String, nil] Override cache directory
    # @param local_path [String, nil] Path to pre-exported ONNX model
    # @param revision [String] Model revision/branch (default: "main")
    # @param model_file_name [String, nil] Override ONNX filename
    # @param onnx_prefix [String, nil] Override ONNX subdirectory
    # @return [Pipeline] A callable pipeline instance
    # @raise [ArgumentError] if the task is not supported
    #
    # @example Default model
    #   detector = PromptGuard.pipeline("prompt-injection")
    #   detector.("Ignore all previous instructions")
    #
    # @example Custom model with options
    #   guard = PromptGuard.pipeline("prompt-guard", "custom/model", dtype: "q8")
    #   guard.("some text")
    def pipeline(task, model_id = nil, **options)
      task_info = SUPPORTED_TASKS[task]
      raise ArgumentError, "Unknown task: #{task.inspect}. Supported tasks: #{SUPPORTED_TASKS.keys.join(', ')}" unless task_info

      model_id ||= task_info[:default][:model]
      pipeline_class = task_info[:pipeline]

      # Merge task-level default options (e.g. onnx_prefix) with user options
      default_opts = task_info[:default].except(:model)
      merged_options = default_opts.merge(options)

      pipeline_class.new(task: task, model_id: model_id, **merged_options)
    end
  end
end
