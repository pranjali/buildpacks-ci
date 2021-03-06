require 'tmpdir'
require 'fileutils'
require 'webmock/rspec'
require_relative '../../../tasks/build-binary-new/builder'
require_relative '../../../tasks/build-binary-new/source_input'
require_relative '../../../tasks/build-binary-new/build_input'
require_relative '../../../tasks/build-binary-new/build_output'
require_relative '../../../tasks/build-binary-new/artifact_output'
require_relative '../../../tasks/build-binary-new/dep_metadata_output'
require_relative '../../../tasks/build-binary-new/binary_builder_wrapper'

TableTestInput = Struct.new(:dep, :version) do
end

TableTestOutput = Struct.new(:old_file_path, :prefix, :extension) do
end

def createDataJSON(path, name, ver)
  FileUtils.mkdir_p(path)
  filepath = File.join(path, "data.json")
  filepath = File.new(filepath, 'w')
  filepath.puts ('{"source":{"name":"' + name + '","type":"' + name + '"},"version":{"ref":"' + ver.to_s() +'","url":"https://fake.url.com"}}')
  filepath.close
end

describe 'Builder' do
  before(:all) do
    WebMock.disable_net_connect!
  end

  after(:all) do
    WebMock.allow_net_connect!
  end

  subject! { Builder.new }

  let(:binary_builder) { double(BinaryBuilderWrapper) }
  let(:build_input) { double(BuildInput) }
  let(:build_output) { double(BuildOutput) }
  let(:artifact_output) { double(ArtifactOutput) }
  let(:dep_metadata_output) { double(DepMetadataOutput) }

  context 'when using the old binary-builder' do
    {
      TableTestInput.new('bundler', '2.7.14')     => TableTestOutput.new('/fake-binary-builder/bundler-2.7.14.tgz', 'bundler_2.7.14_linux_noarch_cflinuxfs2', 'tgz'),
      TableTestInput.new('hwc', '2.7.14')         => TableTestOutput.new('/fake-binary-builder/hwc-2.7.14-windows-x86-64.zip', 'hwc_2.7.14_windows_x86-64_any-stack', 'zip'),
      TableTestInput.new('dep', '2.7.14')         => TableTestOutput.new('/fake-binary-builder/dep-v2.7.14-linux-x64.tgz', 'dep_2.7.14_linux_x64_cflinuxfs2', 'tgz'),
      TableTestInput.new('glide', '2.7.14')       => TableTestOutput.new('/fake-binary-builder/glide-v2.7.14-linux-x64.tgz', 'glide_2.7.14_linux_x64_cflinuxfs2', 'tgz'),
      TableTestInput.new('godep', '2.7.14')       => TableTestOutput.new('/fake-binary-builder/godep-v2.7.14-linux-x64.tgz', 'godep_2.7.14_linux_x64_cflinuxfs2', 'tgz'),
      TableTestInput.new('go', '2.7.14')          => TableTestOutput.new('/fake-binary-builder/go2.7.14.linux-amd64.tar.gz', 'go_2.7.14_linux_x64_cflinuxfs2', 'tar.gz'),
      TableTestInput.new('node', '2.7.14')        => TableTestOutput.new('/fake-binary-builder/node-2.7.14-linux-x64.tgz', 'node_2.7.14_linux_x64_cflinuxfs2', 'tgz'),
      TableTestInput.new('httpd', '2.7.14')       => TableTestOutput.new('/fake-binary-builder/httpd-2.7.14-linux-x64.tgz', 'httpd_2.7.14_linux_x64_cflinuxfs2', 'tgz'),
      TableTestInput.new('ruby', '2.7.14')        => TableTestOutput.new('/fake-binary-builder/ruby-2.7.14-linux-x64.tgz', 'ruby_2.7.14_linux_x64_cflinuxfs2', 'tgz'),
      TableTestInput.new('jruby', '9.2.0')        => TableTestOutput.new('/fake-binary-builder/jruby-9.2.0-ruby-2.5-linux-x64.tgz', 'jruby_9.2.0-ruby-2.5_linux_x64_cflinuxfs2', 'tgz'),
    }.each do |input, output|
      describe "to build #{input.dep}" do
        let(:source_input) { SourceInput.new(input.dep, 'https://fake.com', input.version, 'fake-md5', nil) }

        before do
          allow(binary_builder).to receive(:base_dir).and_return '/fake-binary-builder'

          if input.dep != 'php' && input.dep != 'jruby'
            expect(binary_builder).to receive(:build).with source_input
          elsif input.dep == 'php'
            expect(binary_builder).to receive(:build).with(source_input, anything)
          else
            full_version = "#{source_input.version}-ruby-2.5"
            expect(binary_builder).to receive(:build) {|src| expect(src.version).to eq(full_version)}
          end

          expect(dep_metadata_output).to receive(:write_metadata)
            .with('fake-url', any_args)

          allow(build_input).to receive(:tracker_story_id).and_return 'fake-story-id'
          expect(build_input).to receive(:copy_to_build_output)

          allow(Sha).to receive(:get_sha_from_text_file)
          expect(Sha).to receive(:get_sha).and_return('some-bogus-sha256').at_most(1).times

          allow(Archive).to receive(:strip_top_level_directory_from_tar)
          allow(Archive).to receive(:strip_top_level_directory_from_zip)

          allow(build_output).to receive(:add_output)
            .with("#{input.version}-bionic.json", any_args)

          expect(build_output).to receive(:add_output)
            .with("#{input.version}-cflinuxfs2.json",
              {
                tracker_story_id: 'fake-story-id',
                version:          input.version,
                source:           { url: 'https://fake.com', md5: 'fake-md5', sha256: 'some-bogus-sha256' },
                sha256:           'fake-sha256',
                url:              'fake-url'
              }
            )

          expect(build_output).to receive(:commit_outputs)
            .with("Build #{input.dep} - #{input.version} - cflinuxfs2 [#fake-story-id]")
        end

        it 'should build correctly' do
          expect(artifact_output).to receive(:move_dependency)
            .with(input.dep, output.old_file_path, output.prefix)
            .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end
    end

    context 'php' do
      let(:source_input) { SourceInput.new('php', 'https://fake.com', '7.3.0', nil, 'fake-sha256') }
      let(:php_extensions_dir) { Dir.mktmpdir('builder_php_extensions') }

      before do
        File.open(File.join(php_extensions_dir, 'php7-base-extensions.yml'), 'w') do |f|
          f.puts 'native_modules:'
          f.puts '- name: dep1'
          f.puts '  version: 1.0.0'
          f.puts '- name: bad-dep'
          f.puts '  version: 1.0.0'
          f.puts 'extensions:'
          f.puts '- name: bad-dep'
          f.puts '  version: 1.0.0'
          f.puts '- name: dep2'
          f.puts '  version: 2.0.0'
        end
        File.open(File.join(php_extensions_dir, 'php73-extensions-patch.yml'), 'w') do |f|
          f.puts 'native_modules:'
          f.puts '  exclusions:'
          f.puts '  - name: bad-dep'
          f.puts '  additions:'
          f.puts '  - name: dep3'
          f.puts '    version: 3.0.0'
          f.puts 'extensions:'
          f.puts '  exclusions:'
          f.puts '  - name: bad-dep'
          f.puts '  additions:'
          f.puts '  - name: dep2'
          f.puts '    version: 2.2.2'
          f.puts '  - name: dep4'
          f.puts '    version: 4.0.0'
        end
      end

      after do
        FileUtils.remove_dir(php_extensions_dir)
      end

      it 'should build correctly and include module names and versions' do
        allow(binary_builder).to receive(:base_dir).and_return '/fake-binary-builder'
        allow(binary_builder).to receive(:build)

        allow(build_input).to receive(:copy_to_build_output)
        allow(build_input).to receive(:tracker_story_id).and_return 'fake-story-id'

        allow(build_output).to receive(:add_output)
        allow(build_output).to receive(:commit_outputs)

        allow(artifact_output).to receive(:move_dependency)
          .and_return(sha256: 'fake-sha256', url: 'fake-url')

        allow(Archive).to receive(:strip_top_level_directory_from_tar)

        allow(dep_metadata_output).to receive(:write_metadata)
          .with('fake-url', any_args)

        subject.execute(binary_builder, 'cflinuxfs3', source_input, build_input, build_output, artifact_output, dep_metadata_output, php_extensions_dir)

        expect(binary_builder).to have_received(:build).with(source_input, '--php-extensions-file=' + File.join(php_extensions_dir, 'php-final-extensions.yml'))

        expect(artifact_output).to have_received(:move_dependency)
          .with('php', '/fake-binary-builder/php7-7.3.0-linux-x64.tgz', 'php7_7.3.0_linux_x64_cflinuxfs3')

        expect(build_output).to have_received(:add_output)
          .with('7.3.0-cflinuxfs3.json',
                tracker_story_id: 'fake-story-id',
                version:          '7.3.0',
                source:           { url: 'https://fake.com', md5: nil, sha256: 'fake-sha256' },
                sha256:           'fake-sha256',
                url:              'fake-url',
                sub_dependencies: {
                  dep1: { version: '1.0.0' },
                  dep2: { version: '2.2.2' },
                  dep3: { version: '3.0.0' },
                  dep4: { version: '4.0.0' }
                })
        expect(build_output).to have_received(:commit_outputs)
          .with("Build #{source_input.name} - 7.3.0 - cflinuxfs3 [#fake-story-id]")

        expect(Archive).to have_received(:strip_top_level_directory_from_tar).with('/fake-binary-builder/php7-7.3.0-linux-x64.tgz')
      end
    end
  end

  context 'when not using the old binary-builder' do
    before do
      allow(binary_builder).to receive(:base_dir).and_return '/fake-binary-builder'

      allow(build_input).to receive(:tracker_story_id).and_return 'fake-story-id'
      expect(build_input).to receive(:copy_to_build_output)

      expect(dep_metadata_output).to receive(:write_metadata)
        .with('fake-url', any_args)
    end

    context 'third party-hosted deps' do
      before do
        expect(build_output).to receive(:add_output)
          .with("1.0.2-cflinuxfs2.json",
            {
              tracker_story_id: 'fake-story-id',
              version:          '1.0.2',
              source:           { url: 'fake-url', md5: nil, sha256: 'fake-sha256' },
              sha256:           'fake-sha256',
              url:              'fake-url'
            }
          )
        expect(build_output).to receive(:commit_outputs)
          .with("Build #{source_input.name} - 1.0.2 - cflinuxfs2 [#fake-story-id]")
      end

      describe 'CAAPM, appdynamics, minconda2&3' do
        let(:source_input) { SourceInput.new('CAAPM', 'fake-url', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(Sha).to receive(:check_sha)
            .with(source_input)
            .and_return(['abc', 'fake-sha256'])

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end
    end

    context 'Nginx' do
      before do
        expect(build_output).to receive(:add_output)
          .with("1.0.2-cflinuxfs2.json",
            {
              tracker_story_id: 'fake-story-id',
              version:          '1.0.2',
              source:           { url: 'https://fake.com', md5: nil, sha256: 'fake-sha256' },
              sha256:           'fake-sha256',
              url:              'fake-url',
              source_pgp:       'not yet implemented'
            }
          )
        expect(build_output).to receive(:commit_outputs)
          .with("Build #{source_input.name} - 1.0.2 - cflinuxfs2 [#fake-story-id]")
      end

      describe 'nginx' do
        let(:source_input) { SourceInput.new('nginx', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_nginx)
            .with(source_input,'cflinuxfs2', false)
            .and_return 'fake-source-sha-123'

          expect(artifact_output).to receive(:move_dependency)
            .with('nginx', 'artifacts/nginx-1.0.2.tgz', 'nginx_1.0.2_linux_x64_cflinuxfs2')
            .and_return(sha256: 'fake-sha256', url: 'fake-url')

          expect(Archive).to receive(:strip_top_level_directory_from_tar)
            .with('artifacts/nginx-1.0.2.tgz')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end

      describe 'nginx-static' do
        let(:source_input) { SourceInput.new('nginx-static', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_nginx)
                                         .with(source_input, 'cflinuxfs2', true)
                                         .and_return 'fake-source-sha-123'

          expect(artifact_output).to receive(:move_dependency)
                                         .with('nginx-static', 'artifacts/nginx-1.0.2.tgz', 'nginx-static_1.0.2_linux_x64_cflinuxfs2')
                                         .and_return(sha256: 'fake-sha256', url: 'fake-url')

          expect(Archive).to receive(:strip_top_level_directory_from_tar)
            .with('artifacts/nginx-1.0.2.tgz')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end
    end

    context "Python" do
      before do
        expect(build_output).to receive(:add_output)
                                    .with("1.0.2-cflinuxfs3.json",
                                          {
                                              tracker_story_id: 'fake-story-id',
                                              version:          '1.0.2',
                                              source:           { url: 'https://fake.com', md5: nil, sha256: 'fake-sha256' },
                                              sha256:           'fake-sha256',
                                              url:              'fake-url',
                                          }
                                    )
        expect(build_output).to receive(:commit_outputs)
                                    .with("Build #{source_input.name} - 1.0.2 - cflinuxfs3 [#fake-story-id]")
      end

      context 'building python with binary-builder-new' do
        let(:source_input) { SourceInput.new('python', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }
        it 'should build correctly' do


          expect(DependencyBuild).to receive(:build_python)
                                         .with(source_input, 'cflinuxfs3')
                                         .and_return 'fake-source-sha-123'

          expect(artifact_output).to receive(:move_dependency)
                                         .with('python', 'artifacts/python-1.0.2.tgz', 'python_1.0.2_linux_x64_cflinuxfs3')
                                         .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs3', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end
    end

    context 'and no git commit sha' do
      before do
        expect(build_output).to receive(:add_output)
          .with("1.0.2-cflinuxfs2.json",
            {
              tracker_story_id: 'fake-story-id',
              version:          '1.0.2',
              source:           { url: 'https://fake.com', md5: nil, sha256: 'fake-sha256' },
              sha256:           'fake-sha256',
              url:              'fake-url'
            }
          )
        expect(build_output).to receive(:commit_outputs)
          .with("Build #{source_input.name} - 1.0.2 - cflinuxfs2 [#fake-story-id]")
      end

      describe 'to build composer' do
        let(:source_input) { SourceInput.new('composer', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(artifact_output).to receive(:move_dependency)
            .with('composer', 'source/composer.phar', 'composer_1.0.2_linux_noarch_any-stack')
            .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end

      describe 'to build pipenv' do
        let(:source_input) { SourceInput.new('pipenv', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_pipenv)
            .with(source_input)
            .and_return '/build-dir/fake-pipenv-1234.tar.gz'

          expect(artifact_output).to receive(:move_dependency)
            .with('pipenv', '/build-dir/fake-pipenv-1234.tar.gz', 'pipenv_1.0.2_linux_noarch_cflinuxfs2')
            .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end

      describe 'to build libunwind' do
        let(:source_input) { SourceInput.new('libunwind', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_libunwind)
            .with(source_input)
            .and_return '/build-dir/fake-libunwind-1234.tar.gz'

          expect(artifact_output).to receive(:move_dependency)
            .with('libunwind', '/build-dir/fake-libunwind-1234.tar.gz', 'libunwind_1.0.2_linux_noarch_cflinuxfs2')
            .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end

      describe 'to build dotnet-sdk' do
        let(:source_input) { SourceInput.new('dotnet-sdk', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_dotnet_sdk)
                                       .with(source_input)
                                       .and_return '/tmp/dotnet-sdk.1.0.2.linux-amd64.tar.xz'

          expect(artifact_output).to receive(:move_dependency)
                                       .with('dotnet-sdk', '/tmp/dotnet-sdk.1.0.2.linux-amd64.tar.xz', 'dotnet-sdk_1.0.2_linux_x64_cflinuxfs2')
                                       .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end

      describe 'to build dotnet-runtime' do
        let(:source_input) { SourceInput.new('dotnet-runtime', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_dotnet_runtime)
                                       .with(source_input)
                                       .and_return '/tmp/dotnet-runtime.1.0.2.linux-amd64.tar.xz'

          expect(artifact_output).to receive(:move_dependency)
                                       .with('dotnet-runtime', '/tmp/dotnet-runtime.1.0.2.linux-amd64.tar.xz', 'dotnet-runtime_1.0.2_linux_x64_cflinuxfs2')
                                       .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end

      describe 'to build dotnet-aspnetcore' do
        let(:source_input) { SourceInput.new('dotnet-aspnetcore', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_dotnet_aspnetcore)
                                       .with(source_input)
                                       .and_return '/tmp/dotnet-aspnetcore.1.0.2.linux-amd64.tar.xz'

          expect(artifact_output).to receive(:move_dependency)
                                       .with('dotnet-aspnetcore', '/tmp/dotnet-aspnetcore.1.0.2.linux-amd64.tar.xz', 'dotnet-aspnetcore_1.0.2_linux_x64_cflinuxfs2')
                                       .and_return(sha256: 'fake-sha256', url: 'fake-url')

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end
      end
    end

    context 'and a git commit sha' do
      describe 'to build r' do
        before do
          expect(build_output).to receive(:add_output)
                                    .with("1.0.2-cflinuxfs2.json",
                                      {
                                        tracker_story_id: 'fake-story-id',
                                        version:          '1.0.2',
                                        source:           { url: 'https://fake.com', md5: nil, sha256: 'fake-sha256' },
                                        sha256:           'fake-sha256',
                                        url:              'fake-url',
                                        git_commit_sha:   'fake-source-sha-123',
                                        sub_dependencies: {
                                          forecast: {
                                            source: {
                                              url: 'https://fake.url.com',
                                              sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                                            },
                                            version: '8.4'},
                                          plumber: {
                                            source: {
                                              url: 'https://fake.url.com',
                                              sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                                            },
                                            version: '8.5'},
                                          rserve: {
                                            source: {
                                              url: 'https://fake.url.com',
                                              sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                                            },
                                            version: '8.6'},
                                          shiny: {
                                            source: {
                                              url: 'https://fake.url.com',
                                              sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                                            },
                                            version: '8.7'},
                                        },
                                      }
                                    )
          expect(build_output).to receive(:commit_outputs)
                                    .with("Build #{source_input.name} - 1.0.2 - cflinuxfs2 [#fake-story-id]")
        end
        let(:source_input) { SourceInput.new('r', 'https://fake.com', '1.0.2', nil, 'fake-sha256') }

        createDataJSON("source-rserve-latest", "rserve", "8.6")
        createDataJSON("source-plumber-latest", "plumber", "8.5")
        createDataJSON("source-shiny-latest", "shiny", "8.7")
        createDataJSON("source-forecast-latest", "forecast", "8.4")

        after(:each) do
          FileUtils.remove_dir("source-rserve-latest")
          FileUtils.remove_dir("source-plumber-latest")
          FileUtils.remove_dir("source-shiny-latest")
          FileUtils.remove_dir("source-forecast-latest")
        end

        it 'should build correctly' do
          expect(DependencyBuild).to receive(:build_r)
            .with(source_input, "8.4", "8.5", "8.6", "8.7")
            .and_return 'fake-source-sha-123'

          expect(artifact_output).to receive(:move_dependency)
            .with('r', 'artifacts/r-v1.0.2.tgz', 'r_1.0.2_linux_noarch_cflinuxfs2')
            .and_return(sha256: 'fake-sha256', url: 'fake-url')

          stub_request(:get, "https://fake.url.com").
            with(  headers: {
              'Accept'=>'*/*',
              'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
              'Host'=>'fake.url.com',
              'User-Agent'=>'Ruby'
            }).to_return(status: 200, body: "", headers: {}).times(4)

          subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output)
        end

      end
    end
  end

  context 'when skip-commit is true' do
    let(:source_input) { SourceInput.new('CAAPM', 'fake-url', '1.0.2', nil, 'fake-sha256') }

    before do
      allow(build_input).to receive(:tracker_story_id).and_return 'fake-story-id'
      expect(build_output).not_to receive(:add_output)
      expect(build_output).not_to receive(:commit_outputs)

      expect(dep_metadata_output).to receive(:write_metadata)
        .with('fake-url', any_args)
    end

    it 'does not write any build metadata' do
      expect(Sha).to receive(:check_sha)
                       .with(source_input)
                       .and_return(['abc', 'fake-sha256'])

      subject.execute(binary_builder, 'cflinuxfs2', source_input, build_input, build_output, artifact_output, dep_metadata_output, '', true)
    end
  end
end
