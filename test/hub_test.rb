# frozen_string_literal: true

require_relative "test_helper"

class HubTest < Minitest::Test
  include PromptGuardTestHelper

  def test_returns_cached_file_when_exists
    Dir.mktmpdir do |dir|
      # Create a cached file
      model_dir = File.join(dir, "test/model")
      FileUtils.mkdir_p(model_dir)
      cached_file = File.join(model_dir, "tokenizer.json")
      File.write(cached_file, '{"test": true}')

      result = PromptGuard::Utils::Hub.get_model_file(
        "test/model", "tokenizer.json", true, cache_dir: dir
      )

      assert_equal cached_file, result
    end
  end

  def test_raises_when_offline_and_not_cached
    Dir.mktmpdir do |dir|
      PromptGuard.allow_remote_models = false

      err = assert_raises(PromptGuard::Error) do
        PromptGuard::Utils::Hub.get_model_file(
          "test/model", "tokenizer.json", true, cache_dir: dir
        )
      end

      assert_includes err.message, "remote downloads are disabled"
    end
  end

  def test_returns_nil_when_offline_and_not_cached_non_fatal
    Dir.mktmpdir do |dir|
      PromptGuard.allow_remote_models = false

      result = PromptGuard::Utils::Hub.get_model_file(
        "test/model", "tokenizer.json", false, cache_dir: dir
      )

      assert_nil result
    end
  end

  def test_returns_nil_on_download_failure_non_fatal
    Dir.mktmpdir do |dir|
      PromptGuard.allow_remote_models = true
      # Use a host that will fail
      PromptGuard.remote_host = "https://localhost:1"

      result = PromptGuard::Utils::Hub.get_model_file(
        "test/model", "nonexistent.json", false, cache_dir: dir
      )

      assert_nil result
    end
  end

  def test_get_model_json_parses_cached_file
    Dir.mktmpdir do |dir|
      model_dir = File.join(dir, "test/model")
      FileUtils.mkdir_p(model_dir)
      File.write(File.join(model_dir, "config.json"), '{"model_type": "bert", "num_labels": 2}')

      result = PromptGuard::Utils::Hub.get_model_json(
        "test/model", "config.json", true, cache_dir: dir
      )

      assert_equal "bert", result["model_type"]
      assert_equal 2, result["num_labels"]
    end
  end

  def test_get_model_json_returns_empty_hash_non_fatal
    Dir.mktmpdir do |dir|
      PromptGuard.allow_remote_models = false

      result = PromptGuard::Utils::Hub.get_model_json(
        "test/model", "missing.json", false, cache_dir: dir
      )

      assert_equal({}, result)
    end
  end

  def test_creates_intermediate_directories
    Dir.mktmpdir do |dir|
      model_dir = File.join(dir, "owner/model")
      FileUtils.mkdir_p(model_dir)
      # Create the cached file to avoid actual download
      onnx_dir = File.join(model_dir, "onnx")
      FileUtils.mkdir_p(onnx_dir)
      File.write(File.join(onnx_dir, "model.onnx"), "fake")

      result = PromptGuard::Utils::Hub.get_model_file(
        "owner/model", "onnx/model.onnx", true, cache_dir: dir
      )

      assert File.exist?(result)
      assert_equal File.join(onnx_dir, "model.onnx"), result
    end
  end

  def test_atomic_write_cleans_up_incomplete_on_failure
    Dir.mktmpdir do |dir|
      PromptGuard.allow_remote_models = true
      # Use a host that will fail to trigger download error
      PromptGuard.remote_host = "https://localhost:1"

      PromptGuard::Utils::Hub.get_model_file(
        "test/model", "file.onnx", false, cache_dir: dir
      )

      # Verify no .incomplete file is left behind
      incomplete = File.join(dir, "test/model", "file.onnx.incomplete")
      refute File.exist?(incomplete)
    end
  end
end
