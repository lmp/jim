require 'helper'

class TestJimInstaller < Test::Unit::TestCase

  context "Jim::Installer" do
    setup do
      # clear the tmp dir
      FileUtils.rm_rf(tmp_path) if File.exist?(tmp_path)
      FileUtils.rm_rf(JIM_TMP_ROOT) if File.exist?(JIM_TMP_ROOT)
    end

    context "initializing" do
      setup do
        @installer = Jim::Installer.new('fetchpath', 'installpath', {:version => '1.1'})
      end

      should "set fetch path" do
        assert_equal Pathname.new('fetchpath'), @installer.fetch_path
      end

      should "set install path" do
        assert_equal Pathname.new('installpath'), @installer.install_path
      end

      should "set options" do
        assert_equal({:version => '1.1'}, @installer.options)
      end

    end

    context "fetch" do
      setup do
        @url = "http://jquery.com/download/jquery-1.4.1.js"
        FakeWeb.register_uri(:get, @url, :body => fixture('jquery-1.4.1.js'))
      end

      should "fetch remote file" do
        installer = Jim::Installer.new(@url, tmp_path)
        assert installer.fetch
      end

      should "fetch local file" do
        installer = Jim::Installer.new(fixture_path('jquery-1.4.1.js'), tmp_path)
        fetched_path = installer.fetch
        assert_dir fetched_path.dirname
        assert_equal 'jquery-1.4.1.js', fetched_path.basename.to_s
      end

    end

    context "determine_name_and_version" do

      should "determine from filename" do
        installer = Jim::Installer.new(fixture_path('jquery-1.4.1.js'), tmp_path)
        assert installer.fetch
        assert installer.determine_name_and_version
        assert_equal '1.4.1', installer.version
        assert_equal 'jquery', installer.name
      end

      should "determine from package.json" do
        installer = Jim::Installer.new(fixture_path('mustache.js'), tmp_path)
        assert installer.fetch
        assert installer.determine_name_and_version
        assert_equal "0.2.2", installer.version
        assert_equal "mustache", installer.name
      end

      should "determine from file comments" do
        installer = Jim::Installer.new(fixture_path('infoincomments.js'), tmp_path)
        assert installer.fetch
        assert installer.determine_name_and_version
        assert_equal 'myproject', installer.name
        assert_equal '1.2.2', installer.version
      end

      should "determine from options" do
        installer = Jim::Installer.new(fixture_path('jquery-1.4.1.js'), tmp_path, :name => 'myproject', :version => '1.1.1')
        assert installer.fetch
        assert installer.determine_name_and_version
        assert_equal 'myproject', installer.name
        assert_equal '1.1.1', installer.version
      end

      should "have default version if version can not be determined" do
        installer = Jim::Installer.new(fixture_path('noversion.js'), tmp_path)
        assert installer.fetch
        assert installer.determine_name_and_version
        assert_equal 'noversion', installer.name
        assert_equal '0', installer.version
      end

    end

    context "install" do

      context "with a single file" do
        setup do
          @installer = Jim::Installer.new(fixture_path('jquery-1.4.1.js'), tmp_path)
          assert @installer.install
          @install_path = File.join(tmp_path, 'lib', 'jquery-1.4.1')
        end

        should "install a package.json" do
          assert_readable @install_path,  'package.json'
          assert_file_contents(/\"name\"\:\s*\"jquery\"/, @install_path,  'package.json')
        end

        should "move file into install path at name/version" do
          assert_dir @install_path
          assert_readable @install_path, 'jquery.js'
          assert_equal fixture('jquery-1.4.1.js'), File.read(File.join(@install_path, 'jquery.js'))
        end
      end

      context "with a file that seems to be installed already" do
        should "return false" do
          @installer = Jim::Installer.new(fixture_path('jquery-1.4.1.js'), tmp_path)
          assert @installer.install
          @install_path = File.join(tmp_path, 'lib', 'jquery-1.4.1')
          assert_readable @install_path, 'jquery.js'
          @installer = Jim::Installer.new(fixture_path('jquery.color.js'), tmp_path, :name => 'jquery', :version => '1.4.1')
          assert !@installer.install
        end
      end

      context "with a duplicate file" do
        should "skip install but not raise error" do
          @installer = Jim::Installer.new(fixture_path('jquery-1.4.1.js'), tmp_path)
          assert @installer.install
          @install_path = File.join(tmp_path, 'lib', 'jquery-1.4.1')
          assert_readable @install_path, 'jquery.js'
          @installer = Jim::Installer.new(fixture_path('jquery-1.4.1.js'), tmp_path)
          assert @installer.install
          assert_readable @install_path, 'jquery.js'
        end
      end

      context "with a zip" do
        setup do
          @url = "http://jquery.com/download/jquery.metadata-2.0.zip"
          FakeWeb.register_uri(:get, @url, :body => fixture('jquery.metadata-2.0.zip'))
          @installer = Jim::Installer.new(@url, tmp_path)
          @paths = @installer.install
          @install_path = tmp_path + 'lib'
        end

        should "return an array of paths" do
          assert @paths.is_a?(Array)
          assert @paths.all? {|p| p.is_a?(Pathname) }
        end

        should "install each js file found separately" do
          assert_dir tmp_path, 'lib', 'jquery.metadata-2.0'
          assert_readable tmp_path, 'lib', 'jquery.metadata-2.0', 'jquery.metadata.js'
          assert_readable tmp_path, 'lib', 'jquery.metadata.min-2.0', 'jquery.metadata.min.js'
          assert_readable tmp_path, 'lib', 'jquery.metadata.pack-2.0', 'jquery.metadata.pack.js'
        end

        should "not install files found in ignored directories" do
          assert_not_readable tmp_path, 'lib', 'test-2.0', 'test.js'
          assert_not_readable tmp_path, 'lib', 'test-0', 'test.js'
        end

        should "install a package.json" do
          json_path = @install_path + 'jquery.metadata-2.0' + 'package.json'
          assert_readable json_path
          assert_file_contents(/\"name\"\:\s*\"jquery\.metadata\"/, json_path)
        end

      end

      context "with a dir" do
        setup do
          @installer = Jim::Installer.new(fixture_path('sammy-0.5.0'), tmp_path)
          @paths = @installer.install
          @install_path = tmp_path + 'lib'
        end

        should "return an array of paths" do
          assert @paths.is_a?(Array)
          assert @paths.all? {|p| p.is_a?(Pathname) }
        end

        should "install each js file found separately" do
          assert_dir tmp_path, 'lib', 'sammy-0.5.0'
          assert_readable tmp_path, 'lib', 'sammy-0.5.0', 'sammy.js'
          assert_readable tmp_path, 'lib', 'sammy.template-0.5.0', 'sammy.template.js'
          assert_readable tmp_path, 'lib', 'sammy.haml-0.5.0', 'sammy.haml.js'
        end

        should "not install files found in ignored directories" do
          assert_not_readable tmp_path, 'lib', 'qunit-spec-0.5.0', 'qunit-spec.js'
          assert_not_readable tmp_path, 'lib', 'qunit-spec-0', 'qunit-spec.js'
          assert_not_readable tmp_path, 'lib', 'test_sammy_application-0.5.0', 'test_sammy_application.js'
          assert_not_readable tmp_path, 'lib', 'test_sammy_application-0', 'test_sammy_application.js'
        end

        should "install a package.json" do
          json_path = @install_path + 'sammy-0.5.0' + 'package.json'
          assert_readable json_path
          assert_file_contents(/\"name\"\:\s*\"sammy\"/, json_path)
        end
      end

      context "with an existing package.json" do
        setup do
          @installer = Jim::Installer.new(fixture_path('mustache.js'), tmp_path)
          @paths = @installer.install
          @install_path = tmp_path + 'lib'
        end

        should "return an array of paths" do
          assert @paths.is_a?(Array)
          assert @paths.all? {|p| p.is_a?(Pathname) }
        end

        should "install each js file found separately" do
          assert_dir tmp_path, 'lib', 'mustache-0.2.2'
          assert_readable tmp_path, 'lib', 'mustache-0.2.2', 'mustache.js'
        end

        should "merge initial package.json values" do
          json_path = @install_path + 'mustache-0.2.2' + 'package.json'
          assert_readable json_path
          assert_file_contents(/\"name\"\:\s*\"mustache\"/, json_path)
          assert_file_contents(/\"author\"\:\s*\"Jan Lehnardt\"/, json_path)
        end
      end

    end

  end
end
