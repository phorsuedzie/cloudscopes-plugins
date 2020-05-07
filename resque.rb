require 'resque'
require 'resque-scheduler'

category "Resque"

sample_interval 10

Resque.redis = Redis.new

describe_samples do
  queue_sizes = ::Resque.queue_sizes
  queue_name_prefix = "#{ec2.ecs_cluster.rpartition('-').last}_"
  queue_sizes.select! {|k, _| k.start_with?(queue_name_prefix) }
  pending = queue_sizes.values.reduce(&:+) || 0
  workers = ::Resque.workers.select {|w| w.queues.any? {|q| q.start_with?(queue_name_prefix)} }

  ::Resque::Worker.all_workers_with_expired_heartbeats.each do |worker|
    next unless workers.include?(worker)

    # prune code copied from ::Resque::Worker#prune_dead_workers which does too many other things
    job_class = worker.job(false)['payload']['class'] rescue nil
    worker.unregister_worker(::Resque::PruneDeadWorkerDirtyExit.new(worker.to_s, job_class))
    workers -= [worker]
  end
  working = workers.count(&:working?)

  delayed = ::Resque.find_delayed_selection do |args|
    args.any? {|arg| Hash === arg && arg['queue_name'].start_with?(queue_name_prefix) }
  end.count

  opts = {aggregate: {}, dimensions: {ClusterName: ec2.ecs_cluster}}

  sample(**opts, name: "Working", unit: "Count", value: working, storage_resolution: 1)
  sample(**opts, name: "Working low-res", unit: "Count", value: working)
  sample(**opts, name: "Pending", unit: "Count", value: pending, storage_resolution: 1)
  sample(**opts, name: "Pending low-res", unit: "Count", value: pending)
  sample(**opts, name: "Delayed", unit: "Count", value: delayed)
end
