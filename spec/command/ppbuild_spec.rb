require File.expand_path('../../spec_helper', __FILE__)

module Pod
  describe Command::Ppbuild do
    describe 'CLAide' do
      it 'registers it self' do
        Command.parse(%w{ ppbuild }).should.be.instance_of Command::Ppbuild
      end
    end
  end
end

