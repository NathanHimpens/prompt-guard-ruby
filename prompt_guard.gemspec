# frozen_string_literal: true

require_relative "lib/prompt_guard/version"

Gem::Specification.new do |spec|
  spec.name = "prompt_guard"
  spec.version = PromptGuard::VERSION
  spec.summary = "Prompt injection detection for Ruby"
  spec.description = "Detect prompt injection attacks using ONNX models. " \
                     "Protects LLM applications from malicious prompts."
  spec.homepage = "https://github.com/your-username/prompt_guard"
  spec.license = "MIT"

  spec.author = "Klara"
  spec.email = "dev@klarahr.com"

  spec.files = Dir["*.{md,txt}", "LICENSE*", "{lib}/**/*"]
  spec.require_path = "lib"

  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "onnxruntime", ">= 0.9"
  spec.add_dependency "tokenizers", ">= 0.5"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }
end
