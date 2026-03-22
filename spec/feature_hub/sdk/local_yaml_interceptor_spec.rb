# frozen_string_literal: true

require "tempfile"
require "yaml"

RSpec.describe FeatureHub::Sdk::LocalYamlValueInterceptor do
  def with_yaml_file(content)
    file = Tempfile.new(["featurehub-features", ".yaml"])
    file.write(content)
    file.close
    allow(ENV).to receive(:fetch).with("FEATUREHUB_LOCAL_YAML", "featurehub-features.yaml").and_return(file.path)
    yield FeatureHub::Sdk::LocalYamlValueInterceptor.new
  ensure
    file.unlink
  end

  it "returns false when the yaml file does not exist" do
    allow(ENV).to receive(:fetch).with("FEATUREHUB_LOCAL_YAML", "featurehub-features.yaml")
                                 .and_return("/nonexistent.yaml")
    interceptor = FeatureHub::Sdk::LocalYamlValueInterceptor.new
    expect(interceptor.intercepted_value(:MY_FLAG, nil, nil)).to eq([false, nil])
  end

  it "returns false when the key is not in the file" do
    with_yaml_file("flagValues:\n  OTHER: true\n") do |interceptor|
      expect(interceptor.intercepted_value(:MY_FLAG, nil, nil)).to eq([false, nil])
    end
  end

  it "maps a boolean true value" do
    with_yaml_file("flagValues:\n  MY_FLAG: true\n") do |interceptor|
      matched, value = interceptor.intercepted_value(:MY_FLAG, nil, nil)
      expect(matched).to eq(true)
      expect(value).to eq(true)
    end
  end

  it "maps a boolean false value" do
    with_yaml_file("flagValues:\n  MY_FLAG: false\n") do |interceptor|
      matched, value = interceptor.intercepted_value(:MY_FLAG, nil, nil)
      expect(matched).to eq(true)
      expect(value).to eq(false)
    end
  end

  it "maps an integer to a float" do
    with_yaml_file("flagValues:\n  MY_NUM: 42\n") do |interceptor|
      matched, value = interceptor.intercepted_value(:MY_NUM, nil, nil)
      expect(matched).to eq(true)
      expect(value).to eq(42.0)
      expect(value).to be_a(Float)
    end
  end

  it "maps a float value" do
    with_yaml_file("flagValues:\n  MY_NUM: 3.14\n") do |interceptor|
      matched, value = interceptor.intercepted_value(:MY_NUM, nil, nil)
      expect(matched).to eq(true)
      expect(value).to eq(3.14)
    end
  end

  it "maps a string value" do
    with_yaml_file("flagValues:\n  MY_STR: hello\n") do |interceptor|
      matched, value = interceptor.intercepted_value(:MY_STR, nil, nil)
      expect(matched).to eq(true)
      expect(value).to eq("hello")
    end
  end

  it "maps a complex yaml structure to a hash" do
    yaml = "flagValues:\n  MY_JSON:\n    colour: red\n    size: 5\n"
    with_yaml_file(yaml) do |interceptor|
      matched, value = interceptor.intercepted_value(:MY_JSON, nil, nil)
      expect(matched).to eq(true)
      expect(value).to be_a(Hash)
      expect(value["colour"]).to eq("red")
      expect(value["size"]).to eq(5)
    end
  end

  it "accepts an explicit filename" do
    file = Tempfile.new(["explicit", ".yaml"])
    file.write("flagValues:\n  MY_FLAG: true\n")
    file.close
    interceptor = FeatureHub::Sdk::LocalYamlValueInterceptor.new(file.path)
    matched, value = interceptor.intercepted_value(:MY_FLAG, nil, nil)
    expect(matched).to eq(true)
    expect(value).to eq(true)
  ensure
    file.unlink
  end

  it "reads the yaml file path from FEATUREHUB_LOCAL_YAML env var" do
    with_yaml_file("flagValues:\n  FLAG: true\n") do |interceptor|
      matched, value = interceptor.intercepted_value(:FLAG, nil, nil)
      expect(matched).to eq(true)
      expect(value).to eq(true)
    end
  end

  describe "file watching" do
    it "does not start a watcher by default" do
      file = Tempfile.new(["featurehub-features", ".yaml"])
      file.write("flagValues:\n  MY_FLAG: true\n")
      file.close
      interceptor = FeatureHub::Sdk::LocalYamlValueInterceptor.new(file.path)
      expect(interceptor.instance_variable_get(:@watcher)).to be_nil
    ensure
      file.unlink
    end

    it "reloads the file when it changes" do
      file = Tempfile.new(["featurehub-features", ".yaml"])
      file.write("flagValues:\n  MY_FLAG: true\n")
      file.close

      interceptor = FeatureHub::Sdk::LocalYamlValueInterceptor.new(file.path, watch: true, watch_interval: 0.1)

      expect(interceptor.intercepted_value(:MY_FLAG, nil, nil)).to eq([true, true])

      # ensure mtime changes by sleeping at least 1 second (filesystem mtime resolution)
      sleep(1.1)
      File.write(file.path, "flagValues:\n  MY_FLAG: false\n")

      sleep(0.3)
      expect(interceptor.intercepted_value(:MY_FLAG, nil, nil)).to eq([true, false])
    ensure
      interceptor&.close
      file.unlink
    end

    it "picks up new keys added to the file" do
      file = Tempfile.new(["featurehub-features", ".yaml"])
      file.write("flagValues:\n  MY_FLAG: true\n")
      file.close

      interceptor = FeatureHub::Sdk::LocalYamlValueInterceptor.new(file.path, watch: true, watch_interval: 0.1)

      expect(interceptor.intercepted_value(:NEW_KEY, nil, nil)).to eq([false, nil])

      sleep(1.1)
      File.write(file.path, "flagValues:\n  MY_FLAG: true\n  NEW_KEY: hello\n")

      sleep(0.3)
      expect(interceptor.intercepted_value(:NEW_KEY, nil, nil)).to eq([true, "hello"])
    ensure
      interceptor&.close
      file.unlink
    end

    it "stops watching after close is called" do
      file = Tempfile.new(["featurehub-features", ".yaml"])
      file.write("flagValues:\n  MY_FLAG: true\n")
      file.close

      interceptor = FeatureHub::Sdk::LocalYamlValueInterceptor.new(file.path, watch: true, watch_interval: 0.1)
      interceptor.close

      expect(interceptor.instance_variable_get(:@watcher)).to be_nil
    ensure
      file.unlink
    end
  end

  describe "with feature_state type checking" do
    def fs(type)
      { "type" => type }
    end

    it "matches when the yaml boolean type matches the feature state type" do
      with_yaml_file("flagValues:\n  MY_FLAG: true\n") do |interceptor|
        matched, value = interceptor.intercepted_value(:MY_FLAG, nil, fs(FeatureHub::Sdk::FeatureValueType::BOOLEAN))
        expect(matched).to eq(true)
        expect(value).to eq(true)
      end
    end

    it "returns false when the yaml value type does not match the feature state type" do
      with_yaml_file("flagValues:\n  MY_FLAG: true\n") do |interceptor|
        result = interceptor.intercepted_value(:MY_FLAG, nil, fs(FeatureHub::Sdk::FeatureValueType::STRING))
        expect(result).to eq([false, nil])
      end
    end

    it "matches a number value against NUMBER type" do
      with_yaml_file("flagValues:\n  MY_NUM: 7\n") do |interceptor|
        matched, value = interceptor.intercepted_value(:MY_NUM, nil, fs(FeatureHub::Sdk::FeatureValueType::NUMBER))
        expect(matched).to eq(true)
        expect(value).to eq(7.0)
      end
    end

    it "returns false when a number value is checked against BOOLEAN type" do
      with_yaml_file("flagValues:\n  MY_NUM: 7\n") do |interceptor|
        result = interceptor.intercepted_value(:MY_NUM, nil, fs(FeatureHub::Sdk::FeatureValueType::BOOLEAN))
        expect(result).to eq([false, nil])
      end
    end

    it "matches a complex value against JSON type" do
      with_yaml_file("flagValues:\n  MY_JSON:\n    a: 1\n") do |interceptor|
        matched, value = interceptor.intercepted_value(:MY_JSON, nil, fs(FeatureHub::Sdk::FeatureValueType::JSON))
        expect(matched).to eq(true)
        expect(value).to be_a(Hash)
        expect(value["a"]).to eq(1)
      end
    end
  end
end
