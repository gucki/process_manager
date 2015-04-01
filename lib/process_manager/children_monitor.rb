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
    options[:logger] ||= Logger.new(STDOUT)
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
    %x{ps -p #{pid} -orss -h}.strip.to_i / 1024
  end

  def children_pids
    ppid = parent_pid
    return [] unless ppid
    %x{ps --ppid #{parent_pid} -opid h}.split("\n").map{ |pid| pid.strip.to_i }
  end

  def gracefully_kill_child(pid)
    # See http://unicorn.bogomips.org/SIGNALS.html
    # Gracefully exit after finishing the current request. The master process will respawn a worker to replace this one.
    Process.kill("QUIT", pid)
  rescue Errno::ESRCH
    # noop
  end
end
