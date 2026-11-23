# frozen_string_literal: true

# featurehub-protocol.yaml encoding.evaluation_context.context_sha.examples - every SDK reproduces these
RSpec.describe FeatureHub::Sdk::ContextHeader do
  [
    [{}, "", "0"],
    [{ userkey: ["fred"], country: ["nz"] }, "country=nz,userkey=fred",
     "bbaf44b81bc349603f38ece814e9b741fea50e58990db3bd24988ee69eec0603"],
    [{ shop: ["a&b", "c d"] }, "shop=a%26b%2Cc%20d",
     "5f2930219932130037f572be9de4ae5cea89983dba663d9400437a63c1dea22c"],
    [{ "my key": ["x"], "a,b=c": ["y"] }, "a%2Cb%3Dc=y,my%20key=x",
     "a9d1b1707b4d38824da99d1daf06a1b9b24f7d1397d0e138153a946f1575d40a"],
    [{ name: ["Mary Jane+O'Neil ~*()!"] }, "name=Mary%20Jane%2BO'Neil%20~*()!",
     "ff5b8c6d2cc3bbebfc3285b9106b3b300082ecfc5db6d1e4e37e685d0dbbe653"],
    [{ city: ["Zürich"], greeting: ["สวัสดี"] },
     "city=Z%C3%BCrich,greeting=%E0%B8%AA%E0%B8%A7%E0%B8%B1%E0%B8%AA%E0%B8%94%E0%B8%B5",
     "d0f83f10b3e4f06cc9e3d57736c75f91dce1f16ed6035f0b430ccd7f37a50dce"],
    [{ "a!" => ["1"], "a " => ["2"] }, "a!=1,a%20=2",
     "16cab394e891c04ba620debb77279050b6a88e4b58da3bffeb286c4428289e72"],
    [{ userkey: ["fred"], empty: [], gone: [nil] }, "userkey=fred",
     "6a1d1fa42d1c1917552a255a940792205cb62cc2efd6613ab5a3f75d0038518b"],
    [{ version: [3.0], beta: [true], ratio: [0.5] }, "beta=true,ratio=0.5,version=3",
     "b8ec246368e079b0f2b84682231065d867c943e964b5d5acfb557c86cb45b0fb"]
  ].each do |attributes, header, sha|
    it "builds #{header.inspect} for #{attributes}" do
      built = described_class.x_featurehub_header(attributes)
      expect(built).to eq(header)
      expect(described_class.context_sha(built)).to eq(sha)
    end
  end

  it "gives a contextSha of 0 for an empty or missing header" do
    expect(described_class.context_sha("")).to eq("0")
    expect(described_class.context_sha(nil)).to eq("0")
  end

  it "encodes keys and Thai values as encodeURIComponent does" do
    expect(described_class.x_featurehub_header({ "kwong pastry": ["omu&co"], userkey: ["lingling kwong"],
                                                 name: ["กรณ์นภัส"] }))
      .to eq("kwong%20pastry=omu%26co,name=%E0%B8%81%E0%B8%A3%E0%B8%93%E0%B9%8C%E0%B8%99%E0%B8%A0%E0%B8%B1%E0%B8%AA," \
             "userkey=lingling%20kwong")
  end

  it "formats values as JavaScript's String() does" do
    expect(described_class.wire_value(Time.utc(2026, 11, 17, 2, 47, 28))).to eq("2026-11-17T02:47:28.000Z")
    expect(described_class.wire_value(Float::NAN)).to eq("NaN")
    expect(described_class.wire_value(-Float::INFINITY)).to eq("-Infinity")
    expect(described_class.wire_value(2)).to eq("2")
  end
end
