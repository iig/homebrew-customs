class Kafka091 < Formula
  desc "Publish-subscribe messaging rethought as a distributed commit log"
  homepage "https://kafka.apache.org"
  url "http://mirrors.ibiblio.org/apache/kafka/0.9.0.1/kafka-0.9.0.1-src.tgz"
  mirror "https://archive.apache.org/dist/kafka/0.9.0.1/kafka-0.9.0.1-src.tgz"
  sha256 "95d6bcb8fb1ee697b15c262dd9b61d0b47c7c9d1c8ece07205d4c2545ed12596"

  head "https://git-wip-us.apache.org/repos/asf/kafka.git", :branch => "trunk"

  bottle do
    cellar :any_skip_relocation
    sha256 "8808773c5ae7251a75592963271766e969f2faba4feaa0f1259da15c56a30c00" => :el_capitan
    sha256 "d1cbd5529d005643619bb5832edb6f5c9b4a45f9bac8115c79b0bb63886bbabf" => :yosemite
    sha256 "0543a3798af77854d36cc640ecebc6067607be1dbcea6dc60de4adb88cd45261" => :mavericks
  end

  depends_on "gradle"
  depends_on "zookeeper"
  depends_on :java => "1.7+"

  # Related to https://issues.apache.org/jira/browse/KAFKA-2034
  # Since Kafka does not currently set the source or target compability version inside build.gradle
  # if you do not have Java 1.8 installed you cannot used the bottled version of Kafka
  pour_bottle? do
    reason "The bottle requires Java 1.8."
    satisfy { quiet_system("/usr/libexec/java_home --version 1.8 --failfast") }
  end

  def install
    ENV.java_cache

    system "gradle"
    system "gradle", "jar"

    logs = var/"log/kafka"
    inreplace "config/test-log4j.properties", ".File=logs/", ".File=#{logs}/"

    data = var/"lib"
    inreplace "config/server.properties",
      "log.dirs=/tmp/kafka-logs", "log.dirs=#{data}/kafka-logs"

    inreplace "config/zookeeper.properties",
      "dataDir=/tmp/zookeeper", "dataDir=#{data}/zookeeper"

    # Workaround for conflicting slf4j-log4j12 jars (1.7.10 is preferred)
    rm_f "core/build/dependant-libs-2.10.5/slf4j-log4j12-1.7.6.jar"

    # remove Windows scripts
    rm_rf "bin/windows"

    libexec.install %w[clients core examples]

    prefix.install "bin"
    bin.env_script_all_files(libexec/"bin", Language::Java.java_home_env("1.7+"))
    Dir["#{bin}/*.sh"].each { |f| mv f, f.to_s.gsub(/.sh$/, "") }

    mv "config", "kafka"
    etc.install "kafka"
    libexec.install_symlink etc/"kafka" => "config"

    # create directory for kafka stdout+stderr output logs when run by launchd
    (var+"log/kafka").mkpath
  end

  plist_options :manual => "zookeeper-server-start #{HOMEBREW_PREFIX}/etc/kafka/zookeeper.properties; kafka-server-start #{HOMEBREW_PREFIX}/etc/kafka/server.properties"

  def plist; <<-EOS.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>WorkingDirectory</key>
        <string>#{HOMEBREW_PREFIX}</string>
        <key>ProgramArguments</key>
        <array>
            <string>#{opt_bin}/kafka-server-start</string>
            <string>#{etc}/kafka/server.properties</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardErrorPath</key>
        <string>#{var}/log/kafka/kafka_output.log</string>
        <key>StandardOutPath</key>
        <string>#{var}/log/kafka/kafka_output.log</string>
    </dict>
    </plist>
    EOS
  end

  test do
    ENV["LOG_DIR"] = "#{testpath}/kafkalog"

    (testpath/"kafka").mkpath
    cp "#{etc}/kafka/zookeeper.properties", testpath/"kafka"
    cp "#{etc}/kafka/server.properties", testpath/"kafka"
    inreplace "#{testpath}/kafka/zookeeper.properties", "#{var}/lib", testpath
    inreplace "#{testpath}/kafka/server.properties", "#{var}/lib", testpath

    begin
      fork do
        exec "#{bin}/zookeeper-server-start #{testpath}/kafka/zookeeper.properties >/dev/null"
      end

      sleep 5

      fork do
        exec "#{bin}/kafka-server-start #{testpath}/kafka/server.properties >/dev/null"
      end

      sleep 5

      @demo_pid = fork do
        exec "#{libexec}/examples/bin/java-producer-consumer-demo.sh > #{testpath}/kafka/demo.out 2>/dev/null"
      end

      sleep 5
    ensure
      quiet_system "pkill", "-9", "-f", "#{testpath}/kafka/"
    end

    assert_match "Received message: ", IO.read("#{testpath}/kafka/demo.out")
  end
end
