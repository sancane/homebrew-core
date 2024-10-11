class Cppcheck < Formula
  desc "Static analysis of C and C++ code"
  homepage "https://sourceforge.net/projects/cppcheck/"
  url "https://github.com/danmar/cppcheck/archive/refs/tags/2.15.0.tar.gz"
  sha256 "98bcc40ac8062635b492fb096d7815376a176ae26749d6c708083f4637f7c0bb"
  license "GPL-3.0-or-later"
  head "https://github.com/danmar/cppcheck.git", branch: "main"

  # There can be a notable gap between when a version is tagged and a
  # corresponding release is created, so we check the "latest" release instead
  # of the Git tags.
  livecheck do
    url :stable
    strategy :github_latest
  end

  bottle do
    sha256 arm64_sequoia:  "3ea489375f8c4c924b50ccbe0a87d6483f11cc05eac21c6bf72cb8759587b97f"
    sha256 arm64_sonoma:   "9f5ec5154d362414f230ad9b94567fc43472e654282b2d9a70a0a33d5153ab36"
    sha256 arm64_ventura:  "0d3c433850bed501f2c819024ea16065acbec6111ca28141a5afe77704df2945"
    sha256 arm64_monterey: "3a5d4211496ee5c5980725b239a6a896aaa5053415992764a82711679c23bcaa"
    sha256 sonoma:         "bdfc1329eed78facd99a182463bc342d7e6a58bf679492a6a19758fac778c63c"
    sha256 ventura:        "1207bb2fe229239e94c194ee7c7bc8b80ada5e23eebc29145c7ccbb786374e47"
    sha256 monterey:       "fa7dc521b729821186cf9b6a0b846ed7559c03e27533108edc3447de33a0d393"
    sha256 x86_64_linux:   "64be07e02d9965a951e708fc8e3463eb9ab7dca8e27c79e58a72e7e67b76e024"
  end

  depends_on "cmake" => :build
  depends_on "python@3.13" => [:build, :test]
  depends_on "pcre"
  depends_on "tinyxml2"

  uses_from_macos "libxml2"

  def python3
    which("python3.13")
  end

  def install
    args = %W[
      -DHAVE_RULES=ON
      -DUSE_BUNDLED_TINYXML2=OFF
      -DENABLE_OSS_FUZZ=OFF
      -DPYTHON_EXECUTABLE=#{python3}
      -DFILESDIR=#{pkgshare}
    ]

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    # Execution test with an input .cpp file
    test_cpp_file = testpath/"test.cpp"
    test_cpp_file.write <<~EOS
      #include <iostream>
      using namespace std;

      int main()
      {
        cout << "Hello World!" << endl;
        return 0;
      }

      class Example
      {
        public:
          int GetNumber() const;
          explicit Example(int initialNumber);
        private:
          int number;
      };

      Example::Example(int initialNumber)
      {
        number = initialNumber;
      }
    EOS
    system bin/"cppcheck", test_cpp_file

    # Test the "out of bounds" check
    test_cpp_file_check = testpath/"testcheck.cpp"
    test_cpp_file_check.write <<~EOS
      int main()
      {
        char a[10];
        a[10] = 0;
        return 0;
      }
    EOS
    output = shell_output("#{bin}/cppcheck #{test_cpp_file_check} 2>&1")
    assert_match "out of bounds", output

    # Test the addon functionality: sampleaddon.py imports the cppcheckdata python
    # module and uses it to parse a cppcheck dump into an OOP structure. We then
    # check the correct number of detected tokens and function names.
    addons_dir = pkgshare/"addons"
    cppcheck_module = "#{name}data"
    expect_token_count = 51
    expect_function_names = "main,GetNumber,Example"
    assert_parse_message = "Error: sampleaddon.py: failed: can't parse the #{name} dump."

    sample_addon_file = testpath/"sampleaddon.py"
    sample_addon_file.write <<~EOS
      #!/usr/bin/env #{python3}
      """A simple test addon for #{name}, prints function names and token count"""
      import sys
      from importlib import machinery, util
      # Manually import the '#{cppcheck_module}' module
      spec = machinery.PathFinder().find_spec("#{cppcheck_module}", ["#{addons_dir}"])
      cpp_check_data = util.module_from_spec(spec)
      spec.loader.exec_module(cpp_check_data)

      for arg in sys.argv[1:]:
          # Parse the dump file generated by #{name}
          configKlass = cpp_check_data.parsedump(arg)
          if len(configKlass.configurations) == 0:
              sys.exit("#{assert_parse_message}") # Parse failure
          fConfig = configKlass.configurations[0]
          # Pick and join the function names in a string, separated by ','
          detected_functions = ','.join(fn.name for fn in fConfig.functions)
          detected_token_count = len(fConfig.tokenlist)
          # Print the function names on the first line and the token count on the second
          print("%s\\n%s" %(detected_functions, detected_token_count))
    EOS

    system bin/"cppcheck", "--dump", test_cpp_file
    test_cpp_file_dump = "#{test_cpp_file}.dump"
    assert_predicate testpath/test_cpp_file_dump, :exist?
    output = shell_output("#{python3} #{sample_addon_file} #{test_cpp_file_dump}")
    assert_match "#{expect_function_names}\n#{expect_token_count}", output
  end
end
