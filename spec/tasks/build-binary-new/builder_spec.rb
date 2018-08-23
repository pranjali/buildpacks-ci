require 'tmpdir'
require 'fileutils'
require_relative '../../../tasks/build-binary-new/builder'
require_relative '../../../tasks/build-binary-new/source_input'
require_relative '../../../tasks/build-binary-new/build_input'
require_relative '../../../tasks/build-binary-new/build_output'
require_relative '../../../tasks/build-binary-new/artifact_output'
require_relative '../../../tasks/build-binary-new/binary_builder_wrapper'

TableTestInput = Struct.new(:dep, :version) do
end

TableTestOutput = Struct.new(:old_file_path, :prefix, :extension) do
end

describe 'Builder' do
  subject { Builder.new }

  let(:build_input) { double(BuildInput) }
  let(:build_output) { double(BuildOutput) }
  let(:artifact_output) { double(ArtifactOutput) }

  context 'when using the old binary-builder' do
    let(:binary_builder) { double(BinaryBuilderWrapper) }

    {
      TableTestInput.new('bundler', '2.7.14') => TableTestOutput.new('/fake-binary-builder/bundler-2.7.14.tgz', 'bundler-2.7.14-cflinuxfs2', 'tgz'),
      TableTestInput.new('python', '2.7.14')  => TableTestOutput.new('/fake-binary-builder/python-2.7.14-linux-x64.tgz', 'python-2.7.14-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('hwc', '2.7.14')     => TableTestOutput.new('/fake-binary-builder/hwc-2.7.14-windows-amd64.zip', 'hwc-2.7.14-windows-amd64', 'zip'),
      TableTestInput.new('dep', '2.7.14')     => TableTestOutput.new('/fake-binary-builder/dep-v2.7.14-linux-x64.tgz', 'dep-v2.7.14-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('glide', '2.7.14')   => TableTestOutput.new('/fake-binary-builder/glide-v2.7.14-linux-x64.tgz', 'glide-v2.7.14-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('godep', '2.7.14')   => TableTestOutput.new('/fake-binary-builder/godep-v2.7.14-linux-x64.tgz', 'godep-v2.7.14-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('go', '2.7.14')      => TableTestOutput.new('/fake-binary-builder/go2.7.14.linux-amd64.tar.gz', 'go2.7.14.linux-amd64-cflinuxfs2', 'tar.gz'),
      TableTestInput.new('node', '2.7.14')    => TableTestOutput.new('/fake-binary-builder/node-2.7.14-linux-x64.tgz', 'node-2.7.14-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('httpd', '2.7.14')   => TableTestOutput.new('/fake-binary-builder/httpd-2.7.14-linux-x64.tgz', 'httpd-2.7.14-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('ruby', '2.7.14')    => TableTestOutput.new('/fake-binary-builder/ruby-2.7.14-linux-x64.tgz', 'ruby-2.7.14-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('jruby', '9.2.0')    => TableTestOutput.new('/fake-binary-builder/jruby-9.2.0_ruby-2.5-linux-x64.tgz', 'jruby-9.2.0_ruby-2.5-linux-x64-cflinuxfs2', 'tgz'),
      TableTestInput.new('php', '7.0.0')      => TableTestOutput.new('/fake-binary-builder/php7-7.0.0-linux-x64.tgz', 'php7-7.0.0-linux-x64-cflinuxfs2', 'tgz'),
    }.each do |input, output|
      describe "to build #{input.dep}" do
        let(:source_input) { SourceInput.new(input.dep, 'https://fake.com', input.version, 'fake-md5', '') }

        before do
          allow(binary_builder).to receive(:base_dir).and_return '/fake-binary-builder'

          if input.dep != 'php'
            expect(binary_builder).to receive(:build).with source_input
          else
            expect(binary_builder).to receive(:build).with(source_input, anything)
          end

          expect(build_input).to receive(:tracker_story_id).and_return 'fake-story-id'
          expect(build_input).to receive(:copy_to_build_output)

          expect(build_output).to receive(:git_add_and_commit)
            .with(
              tracker_story_id: 'fake-story-id',
              version:          input.version,
              source:           { url: 'https://fake.com', md5: 'fake-md5', sha256: '' },
              sha256:           'fake-sha256',
              url:              'fake-url'
            )
        end

        it 'should build correctly' do
          dep_name = input.dep == 'php' ? 'php7' : input.dep
          expect(artifact_output).to receive(:move_dependency)
            .with(dep_name, output.old_file_path, output.prefix, output.extension)
            .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output)
        end
      end
    end
  end
end