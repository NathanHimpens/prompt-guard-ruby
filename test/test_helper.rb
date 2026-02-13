# frozen_string_literal: true

gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require_relative "../lib/prompt_guard"

module PromptGuardTestHelper
  def setup
    @original_logger = PromptGuard.instance_variable_get(:@logger)
    @original_cache_dir = PromptGuard.instance_variable_get(:@cache_dir)
    @original_remote_host = PromptGuard.instance_variable_get(:@remote_host)
    @original_allow_remote = PromptGuard.instance_variable_get(:@allow_remote_models) if PromptGuard.instance_variable_defined?(:@allow_remote_models)
    @had_allow_remote = PromptGuard.instance_variable_defined?(:@allow_remote_models)
  end

  def teardown
    PromptGuard.instance_variable_set(:@logger, @original_logger)
    PromptGuard.instance_variable_set(:@cache_dir, @original_cache_dir)
    PromptGuard.instance_variable_set(:@remote_host, @original_remote_host)
    if @had_allow_remote
      PromptGuard.instance_variable_set(:@allow_remote_models, @original_allow_remote)
    else
      PromptGuard.remove_instance_variable(:@allow_remote_models) if PromptGuard.instance_variable_defined?(:@allow_remote_models)
    end
  end
end
