require 'spec_helper'

describe BootstrapCfPlugin::DirectorCheck do
  subject(:check_director) { described_class.check }

  describe "::check" do
    context "when unable to access the director status" do
      before do
        described_class.stub(:system).with("bosh -n status") { false }
      end

      it "should raise an error if unable to get the director status" do
        expect {
          check_director
        }.to raise_error("Unable to access the director status")
      end
    end

    context "when able to access the director status" do
      before do
        described_class.stub(:system).with("bosh -n status") { true }
      end

      it "should not raise an error if director status call succeeds" do
        expect {
          check_director
        }.to_not raise_error
      end
    end
  end
end
