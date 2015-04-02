class ProcessManager::ChildrenMonitor
  attr_reader :options

  def self.run_in_background(options = {})
    new(options).tap do |monitor|
      options[:interval] ||= 30
      Thread.new do
        loop do
          monitor.run
          sleep(options[:interval])
        end
      end
    end
  end

  def initialize(options = {})
    @options = options
    options[:logger] ||= Logger.new(STDOUT).tap do |logger|
      logger.level = Logger::INFO
    end
  end

  def run
    children_pids.each do |pid|
      memory_usage = process_memory_usage(pid)
      if memory_usage > options[:memory_limit]
        logger.info("Child #{pid} uses #{memory_usage} MB of memory, graceful shutdown signaled.")
        gracefully_kill_child(pid)
      else
        logger.debug("Child #{pid} uses #{memory_usage} MB of memory.")
      end
    end
  rescue => e
    logger.error(e)
  end

  def logger
    options[:logger]
  end

  protected

  def parent_pid
    options[:parent_pid] || read_parent_pid
  end

  def read_parent_pid
    File.read(options[:parent_pid_path]).to_i
  rescue Errno::ENOENT
    nil
  end

  def process_memory_usage(pid)
    File.read("/proc/#{pid}/statm").split(/\s+/)[1].to_i * 4096 / 1024 / 1024
  end

  def children_pids
    ppid = parent_pid
    return [] unless ppid
    [].tap do |list|
      Dir["/proc/*/stat"].each do |path|
        data = File.read(path) rescue
        next unless data
        data = data.split(/\s+/)
        next unless data[3].to_i == ppid
        list << data[0].to_i
      end
    end
  end

  def gracefully_kill_child(pid)
    # See http://unicorn.bogomips.org/SIGNALS.html
    # Gracefully exit after finishing the current request. The master process will respawn a worker to replace this one.
    Process.kill("QUIT", pid)
  rescue Errno::ESRCH
    # noop
  end
end
