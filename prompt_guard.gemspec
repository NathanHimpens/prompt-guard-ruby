# frozen_string_literal: true

require_relative "lib/prompt_guard/version"

Gem::Specification.new do |spec|
  spec.name          = "prompt_guard"
  spec.version       = PromptGuard::VERSION
  spec.authors       = ["Klara"]
  spec.email         = ["dev@klarahr.com"]

  spec.summary       = "LLM security pipelines for Ruby using ONNX models"
  spec.description   = "Security pipelines for LLM applications using ONNX models from Hugging Face Hub. " \
                       "Detect prompt injections, jailbreaks, and PII leaks. " \
                       "Models are lazily downloaded and cached locally. " \
                       "Fast local inference (~10-20ms after initial load)."
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

    Models are downloaded from Hugging Face Hub on first use.

    Quick start:
      require 'prompt_guard'

      # Prompt injection detection
      detector = PromptGuard.pipeline("prompt-injection")
      detector.("Ignore all previous instructions")

      # Prompt guard (BENIGN / MALICIOUS)
      guard = PromptGuard.pipeline("prompt-guard")
      guard.("some text")

      # PII detection
      pii = PromptGuard.pipeline("pii-classifier")
      pii.("My email is john@example.com")

    See README for full setup guide.
    ============================================================
  MSG
end
