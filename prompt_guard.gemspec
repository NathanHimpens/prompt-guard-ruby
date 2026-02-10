# frozen_string_literal: true

require_relative "lib/prompt_guard/version"

Gem::Specification.new do |spec|
  spec.name          = "prompt_guard"
  spec.version       = PromptGuard::VERSION
  spec.authors       = ["Klara"]
  spec.email         = ["dev@klarahr.com"]

  spec.summary       = "Prompt injection detection for Ruby using ONNX models"
  spec.description   = "Detect prompt injection attacks using ONNX models from Hugging Face Hub. " \
                       "Models are lazily downloaded and cached locally. " \
                       "Protects LLM applications from malicious prompts with " \
                       "fast local inference (~10-20ms after initial load)."
  spec.homepage      = "https://github.com/NathanHimpens/prompt-guard-ruby"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }

  # Include files tracked by git, excluding tests, CI configs, and agent dirs.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .github .cursor .ralph])
    end
  end

  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "logger"
  spec.add_dependency "onnxruntime", "~> 0.9"
  spec.add_dependency "tokenizers", "~> 0.5"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"

  spec.post_install_message = <<~MSG
    ============================================================
    prompt_guard installed!

    IMPORTANT: You need an ONNX model for inference.
    The gem downloads model files from Hugging Face Hub, but
    your model must have ONNX files in its repository.

    Option 1 — Use a model with ONNX files on HF Hub:
      require 'prompt_guard'
      PromptGuard.configure(model_id: "your-org/model-with-onnx")
      PromptGuard.injection?("Ignore all instructions")

    Option 2 — Export and use a local model:
      pip install optimum[onnxruntime] transformers torch
      optimum-cli export onnx \\
        --model protectai/deberta-v3-base-injection-onnx \\
        --task text-classification ./prompt-guard-model

      require 'prompt_guard'
      PromptGuard.configure(local_path: './prompt-guard-model')
      PromptGuard.injection?("Ignore all instructions")

    See README for full setup guide.
    ============================================================
  MSG
end
