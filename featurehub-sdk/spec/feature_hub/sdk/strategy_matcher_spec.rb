# frozen_string_literal: true

require "json"

RSpec.describe FeatureHub::Sdk::StrategyMatcher do
  let(:matcher) { FeatureHub::Sdk::MatcherRegistry.new }

  def equals(condition, vals, supplied_val, matches)
    json_data = JSON.parse('{"conditional": "EQUALS", "type": "type", "values": true}')
    json_data["conditional"] = condition
    json_data["type"] = @field_type
    json_data["values"] = vals

    rsa = FeatureHub::Sdk::RolloutStrategyAttribute.new(json_data)

    expect(matcher.find_matcher(rsa).match(supplied_val, rsa)).to eq(matches)
  end

  it "should match boolean strategies correctly" do
    @field_type = "BOOLEAN"

    equals("EQUALS", ["true"], "true", true)
    equals("NOT_EQUALS", ["true"], "true", false)
    equals("NOT_EQUALS", ["true"], "false", true)
    equals("EQUALS", [true], "true", true)
    equals("EQUALS", ["true"], "false", false)
    equals("EQUALS", [true], "false", false)
    equals("EQUALS", [false], "false", true)
    equals("EQUALS", [false], "true", false)
    equals("EQUALS", ["false"], "true", false)
  end

  it "should match string strategies correctly" do
    @field_type = "STRING"

    equals("EQUALS", %w[a b], nil, false)
    equals("EQUALS", %w[a b], "a", true)
    equals("INCLUDES", %w[a b], "a", true)
    equals("NOT_EQUALS", %w[a b], "a", false)
    equals("EXCLUDES", %w[a b], "a", false)
    equals("EXCLUDES", %w[a b], "c", true)
    equals("GREATER", %w[a b], "a", false)
    equals("GREATER_EQUALS", %w[a b], "a", true)
    equals("GREATER", %w[a b], "c", true)
    equals("LESS", %w[a b], "a", true) # < b
    equals("LESS", %w[a b], "1", true)
    equals("LESS", %w[a b], "b", false)
    equals("LESS", %w[a b], "c", false)
    equals("LESS_EQUALS", %w[a b], "a", true)
    equals("LESS_EQUALS", %w[a b], "b", true)
    equals("LESS_EQUALS", %w[a b], "1", true)
    equals("LESS_EQUALS", %w[a b], "c", false)
    equals("STARTS_WITH", ["fr"], "fred", true)
    equals("STARTS_WITH", ["fr"], "mar", false)
    equals("ENDS_WITH", ["ed"], "fred", true)
    equals("ENDS_WITH", ["fred"], "mar", false)
    equals("REGEX", ["(.*)gold(.*)"], "actapus (gold)", true)
    equals("REGEX", ["(.*)gold(.*)"], "(.*)purple(.*)", false)
  end

  it "matches semantic versions correctly" do
    @field_type = "SEMANTIC_VERSION"

    equals("EQUALS", ["2.0.3"], "2.0.3", true)
    equals("EQUALS", ["2.0.3", "2.0.1"], "2.0.3", true)
    equals("EQUALS", ["2.0.3"], "2.0.1", false)
    equals("NOT_EQUALS", ["2.0.3"], "2.0.1", true)
    equals("NOT_EQUALS", ["2.0.3"], "2.0.3", false)
    equals("GREATER", ["2.0.0"], "2.1.0", true)
    equals("GREATER", ["2.0.0"], "2.0.1", true)
    equals("GREATER", ["2.0.0"], "2.0.1", true)
    equals("GREATER", ["2.0.0"], "1.2.1", false)
    equals("GREATER_EQUALS", ["7.1.0"], "7.1.6", true)
    equals("GREATER_EQUALS", ["7.1.6"], "7.1.6", true)
    equals("GREATER_EQUALS", ["7.1.6"], "7.1.2", false)
    equals("LESS", ["2.0.0"], "1.1.0", true)
    equals("LESS", ["2.0.0"], "1.0.1", true)
    equals("LESS", ["2.0.0"], "1.9.9", true)
    equals("LESS", ["2.0.0"], "3.2.1", false)
    equals("LESS_EQUALS", ["7.1.0"], "7.0.6", true)
    equals("LESS_EQUALS", ["7.1.6"], "7.1.2", true)
    equals("LESS_EQUALS", ["7.1.2"], "7.1.6", false)
  end

  it "tests ip addresses correctly" do
    @field_type = "IP_ADDRESS"
    equals("EQUALS", ["192.168.86.75"], "192.168.86.75", true)
    equals("EQUALS", ["192.168.86.75", "10.7.4.8"], "192.168.86.75", true)
    equals("EQUALS", ["192.168.86.75", "10.7.4.8"], "192.168.83.75", false)
    equals("EXCLUDES", ["192.168.86.75", "10.7.4.8"], "192.168.83.75", true)
    equals("EXCLUDES", ["192.168.86.75", "10.7.4.8"], "192.168.86.75", false)
    equals("INCLUDES", ["192.168.86.75", "10.7.4.8"], "192.168.86.75", true)
    equals("EQUALS", ["192.168.86.75"], "192.168.86.72", false)
    equals("NOT_EQUALS", ["192.168.86.75"], "192.168.86.75", false)
    equals("NOT_EQUALS", ["192.168.86.75"], "192.168.86.72", true)
    equals("EQUALS", ["192.168.0.0/16"], "192.168.86.72", true)
    equals("EQUALS", ["192.168.0.0/16"], "192.162.86.72", false)
    equals("EQUALS", ["10.0.0.0/24", "192.168.0.0/16"], "192.168.86.72", true)
    equals("EQUALS", ["10.0.0.0/24", "192.168.0.0/16"], "172.168.86.72", false)
  end

  it "tests dates correctly" do
    @field_type = "DATE"

    equals("EQUALS", %w[2019-01-01 2019-02-01], "2019-02-01", true)
    equals("EQUALS", %w[2019-01-01 2019-02-01], "2019-02-01", true)
    equals("INCLUDES", %w[2019-01-01 2019-02-01], "2019-02-01", true)
    equals("NOT_EQUALS", %w[2019-01-01 2019-02-01], "2019-02-01", false)
    equals("EXCLUDES", %w[2019-01-01 2019-02-01], "2019-02-01", false)

    equals("EQUALS", %w[2019-01-01 2019-02-01], "2019-02-07", false)
    equals("INCLUDES", %w[2019-01-01 2019-02-01], "2019-02-07", false)
    equals("NOT_EQUALS", %w[2019-01-01 2019-02-01], "2019-02-07", true)
    equals("EXCLUDES", %w[2019-01-01 2019-02-01], "2019-02-07", true)

    equals("GREATER", %w[2019-01-01 2019-02-01], "2019-02-07", true)
    equals("GREATER_EQUALS", %w[2019-01-01 2019-02-01], "2019-02-07", true)
    equals("GREATER_EQUALS", %w[2019-01-01 2019-02-01], "2019-02-01", true)
    equals("LESS", %w[2019-01-01 2019-02-01], "2017-02-01", true)
    equals("LESS", %w[2019-01-01 2019-02-01], "2019-02-01", false)
    equals("LESS_EQUALS", %w[2019-01-01 2019-02-01], "2019-02-01", true)
    equals("LESS_EQUALS", %w[2019-01-01 2019-02-01], "2019-03-01", false)
    equals("REGEX", ["2019-.*"], "2019-03-01", true)
    equals("REGEX", ["2019-.*"], "2017-03-01", false)
    equals("REGEX", ["2019-.*", "(.*)-03-(.*)"], "2017-03-01", true)

    equals("STARTS_WITH", %w[2019 2017], "2019-02-07", true)
    equals("STARTS_WITH", ["2019"], "2017-02-07", false)

    equals("ENDS_WITH", ["01"], "2017-02-01", true)
    equals("ENDS_WITH", %w[03 02 2017], "2017-02-01", false)
  end

  it "tests numbers correctly" do
    @field_type = "NUMBER"
    equals("EQUALS", [10, 5], "5", true)
    equals("EQUALS", [5], "5", true)
    equals("EQUALS", [4], "5", false)
    equals("EQUALS", [4, 7], "5", false)
    equals("INCLUDES", [4, 7], "5", false)
    equals("NOT_EQUALS", [23, 100_923], "5", true)
    equals("EXCLUDES", [23, 100_923], "5", true)
    equals("NOT_EQUALS", [5], "5", false)
    equals("GREATER", [2, 4], "5", true)
    equals("GREATER_EQUALS", [2, 5], "5", true)
    equals("GREATER_EQUALS", [4, 5], "5", true)
    equals("LESS_EQUALS", [2, 5], "5", true)
    equals("LESS", [8, 7], "5", true)
    equals("GREATER", [7, 10], "5", false)
    equals("GREATER_EQUALS", [6, 7], "5", false)
    equals("LESS_EQUALS", [2, 3], "5", false)
    equals("LESS", [1, -1], "5", false)
  end

  it "tests datetimes correctly" do
    @field_type = "DATE_TIME"
    # // test equals
    equals("EQUALS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2019-02-01T01:01:01Z", true)
    equals("INCLUDES", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2019-02-01T01:01:01Z", true)
    equals("NOT_EQUALS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2019-02-01T01:01:01Z", false)
    equals("EXCLUDES", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2019-02-01T01:01:01Z", false)

    # // test not equals
    equals("EQUALS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2017-02-01T01:01:01Z", false)
    equals("INCLUDES", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2017-02-01T01:01:01Z", false)
    equals("NOT_EQUALS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2017-02-01T01:01:01Z", true)
    equals("EXCLUDES", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2017-02-01T01:01:01Z", true)

    # // test  less & less =
    equals("LESS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2016-02-01T01:01:01Z", true)
    equals("LESS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2020-02-01T01:01:01Z", false)

    equals("LESS_EQUALS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2019-02-01T01:01:01Z", true)
    equals("LESS_EQUALS", ["2019-01-01T01:01:01Z", "2019-02-01T01:01:01Z"],
           "2020-02-01T01:01:01Z", false)

    equals("REGEX", ["2019-.*"], "2019-07-06T01:01:01Z", true)
    equals("REGEX", ["2019-.*"], "2016-07-06T01:01:01Z", false)
    equals("REGEX", ["2019-.*", "(.*)-03-(.*)"], "2019-07-06T01:01:01Z", true)
    equals("REGEX", ["2019-.*", "(.*)-03-(.*)"], "2014-03-06T01:01:01Z", true)

    equals("STARTS_WITH", %w[2019 2017], "2017-03-06T01:01:01Z", true)
    equals("STARTS_WITH", ["2019"], "2017-03-06T01:01:01Z", false)
    equals("ENDS_WITH", [":01Z"], "2017-03-06T01:01:01Z", true)
    equals("ENDS_WITH", ["03", "2017", "01:01"], "2017-03-06T01:01:01Z", false)
    equals("ENDS_WITH", ["rubbish"], "2017-03-06T01:01:01Z", false)
  end
end
