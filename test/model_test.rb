# frozen_string_literal: true

require_relative "test_helper"

class ModelTest < Minitest::Test
  include PromptGuardTestHelper

  # --- Initialization ---

  def test_model_id_is_stored
    model = PromptGuard::Model.new("deepset/deberta-v3-base-injection")
    assert_equal "deepset/deberta-v3-base-injection", model.model_id
  end

  def test_local_path_is_stored
    model = PromptGuard::Model.new("test/model", local_path: "/my/model")
    assert_equal "/my/model", model.local_path
  end

  # --- Cache directory resolution ---

  def test_default_cache_dir_uses_home
    ENV.delete("PROMPT_GUARD_CACHE_DIR")
    ENV.delete("XDG_CACHE_HOME")
    PromptGuard.cache_dir = nil

    expected = File.join(Dir.home, ".cache", "prompt_guard")
    assert_equal expected, PromptGuard.cache_dir
  end

  def test_cache_dir_from_env_variable
    original = ENV["PROMPT_GUARD_CACHE_DIR"]
    ENV["PROMPT_GUARD_CACHE_DIR"] = "/custom/cache"
    PromptGuard.cache_dir = nil

    assert_equal "/custom/cache", PromptGuard.cache_dir
  ensure
    if original
      ENV["PROMPT_GUARD_CACHE_DIR"] = original
    else
      ENV.delete("PROMPT_GUARD_CACHE_DIR")
    end
  end

  def test_cache_dir_from_xdg
    original_pg = ENV["PROMPT_GUARD_CACHE_DIR"]
    original_xdg = ENV["XDG_CACHE_HOME"]
    ENV.delete("PROMPT_GUARD_CACHE_DIR")
    ENV["XDG_CACHE_HOME"] = "/xdg/cache"
    PromptGuard.cache_dir = nil

    assert_equal "/xdg/cache/prompt_guard", PromptGuard.cache_dir
  ensure
    if original_pg
      ENV["PROMPT_GUARD_CACHE_DIR"] = original_pg
    else
      ENV.delete("PROMPT_GUARD_CACHE_DIR")
    end
    if original_xdg
      ENV["XDG_CACHE_HOME"] = original_xdg
    else
      ENV.delete("XDG_CACHE_HOME")
    end
  end

  def test_custom_cache_dir_via_global_setter
    PromptGuard.cache_dir = "/my/cache"
    assert_equal "/my/cache", PromptGuard.cache_dir
  end

  # --- ready? ---

  def test_ready_returns_true_when_both_files_exist_local
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "model.onnx"), "fake")
      File.write(File.join(dir, "tokenizer.json"), "fake")

      model = PromptGuard::Model.new("test/model", local_path: dir)
      assert model.ready?
    end
  end

  def test_ready_returns_false_when_onnx_missing_local
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tokenizer.json"), "fake")

      model = PromptGuard::Model.new("test/model", local_path: dir)
      refute model.ready?
    end
  end

  def test_ready_returns_false_when_tokenizer_missing_local
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "model.onnx"), "fake")

      model = PromptGuard::Model.new("test/model", local_path: dir)
      refute model.ready?
    end
  end

  def test_ready_returns_true_when_cached_files_exist
    Dir.mktmpdir do |dir|
      # Create cached files in Hub layout
      model_dir = File.join(dir, "test/model")
      onnx_dir = File.join(model_dir, "onnx")
      FileUtils.mkdir_p(onnx_dir)
      File.write(File.join(onnx_dir, "model.onnx"), "fake")
      File.write(File.join(model_dir, "tokenizer.json"), "fake")

      model = PromptGuard::Model.new("test/model", cache_dir: dir)
      assert model.ready?
    end
  end

  def test_ready_returns_false_when_no_cached_files
    Dir.mktmpdir do |dir|
      model = PromptGuard::Model.new("test/model", cache_dir: dir)
      refute model.ready?
    end
  end

  # --- onnx_path ---

  def test_onnx_path_returns_local_path_when_exists
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "model.onnx"), "fake")

      model = PromptGuard::Model.new("test/model", local_path: dir)
      assert_equal File.join(dir, "model.onnx"), model.onnx_path
    end
  end

  def test_onnx_path_raises_when_local_file_missing
    Dir.mktmpdir do |dir|
      model = PromptGuard::Model.new("test/model", local_path: dir)

      err = assert_raises(PromptGuard::ModelNotFoundError) do
        model.onnx_path
      end
      assert_includes err.message, "model.onnx"
    end
  end

  def test_onnx_path_returns_cached_file_when_exists
    Dir.mktmpdir do |dir|
      onnx_dir = File.join(dir, "test/model", "onnx")
      FileUtils.mkdir_p(onnx_dir)
      File.write(File.join(onnx_dir, "model.onnx"), "fake")

      model = PromptGuard::Model.new("test/model", cache_dir: dir)
      assert_equal File.join(onnx_dir, "model.onnx"), model.onnx_path
    end
  end

  # --- tokenizer_path ---

  def test_tokenizer_path_returns_local_path_when_exists
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tokenizer.json"), "{}")

      model = PromptGuard::Model.new("test/model", local_path: dir)
      assert_equal File.join(dir, "tokenizer.json"), model.tokenizer_path
    end
  end

  def test_tokenizer_path_raises_when_local_file_missing
    Dir.mktmpdir do |dir|
      model = PromptGuard::Model.new("test/model", local_path: dir)

      err = assert_raises(PromptGuard::ModelNotFoundError) do
        model.tokenizer_path
      end
      assert_includes err.message, "tokenizer.json"
    end
  end

  # --- ONNX filename construction ---

  def test_default_onnx_filename
    model = PromptGuard::Model.new("test/model")
    assert model.send(:onnx_filename).end_with?("model.onnx")
    assert model.send(:onnx_filename).start_with?("onnx/")
  end

  def test_quantized_onnx_filename
    model = PromptGuard::Model.new("test/model", dtype: "q8")
    assert_equal "onnx/model_quantized.onnx", model.send(:onnx_filename)
  end

  def test_fp16_onnx_filename
    model = PromptGuard::Model.new("test/model", dtype: "fp16")
    assert_equal "onnx/model_fp16.onnx", model.send(:onnx_filename)
  end

  def test_custom_model_file_name
    model = PromptGuard::Model.new("test/model", model_file_name: "custom_model")
    assert_equal "onnx/custom_model.onnx", model.send(:onnx_filename)
  end

  def test_custom_onnx_prefix
    model = PromptGuard::Model.new("test/model", onnx_prefix: "models")
    assert_equal "models/model.onnx", model.send(:onnx_filename)
  end

  # --- Constants ---

  def test_onnx_file_map_is_defined
    assert_kind_of Hash, PromptGuard::Model::ONNX_FILE_MAP
    assert_includes PromptGuard::Model::ONNX_FILE_MAP.keys, "fp32"
    assert_includes PromptGuard::Model::ONNX_FILE_MAP.keys, "q8"
  end

  def test_tokenizer_files_constant_defined
    assert_kind_of Array, PromptGuard::Model::TOKENIZER_FILES
    assert_includes PromptGuard::Model::TOKENIZER_FILES, "tokenizer.json"
    assert_includes PromptGuard::Model::TOKENIZER_FILES, "config.json"
  end
end
