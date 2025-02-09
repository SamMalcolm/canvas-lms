#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

class MultiCache < ActiveSupport::Cache::Store
  def self.cache
    @multi_cache ||= begin
      ha_cache_config = YAML.load(Canvas::DynamicSettings.find(tree: :private, cluster: ApplicationController.cluster)["ha_cache.yml"] || "{}").symbolize_keys || {}
      if (ha_cache_config[:cache_store])
        ha_cache_config[:url] = ha_cache_config[:servers] if ha_cache_config[:servers]
        store = ActiveSupport::Cache.lookup_store(ha_cache_config[:cache_store].to_sym, ha_cache_config)
        store.options.delete(:namespace)
        store
      elsif defined?(ActiveSupport::Cache::RedisCacheStore) && Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore) &&
          defined?(Redis::Distributed) && (store = Rails.cache.redis).is_a?(Redis::Distributed)
        store.instance_variable_get(:@multi_cache) || store.instance_variable_set(:@multi_cache, MultiCache.new(store.ring.nodes))
      else
        Rails.cache
      end
    end
  end

  def self.reset
    @multi_cache = nil
  end

  Canvas::Reloader.on_reload { reset }

  def initialize(ring)
    @ring = ring
    super()
  end

  def fetch(key, options = nil, &block)
    options ||= {}
    # an option to allow populating all nodes in the ring with the
    # same data
    if options[:node] == :all
      calculated_value = nil
      did_calculate = false
      result = nil
      @ring.each do |node|
        options[:node] = node
        if block
          result = super(key, options) do
            calculated_value = yield unless did_calculate
            did_calculate = true
            calculated_value
          end
        else
          result ||= []
          result << super(key, options)
        end
      end
      result
    else
      # this makes the node "sticky" for read/write
      options[:node] = @ring[rand(@ring.length)]
      super(key, options, &block)
    end
  end

  # for compatibility
  def self.copies(key)
    nil
  end

  def self.fetch(key, options = nil, &block)
    cache.fetch(key, options, &block)
  end

  def self.delete(key, options = nil)
    cache.delete(key, options)
  end

  private
  def write_entry(key, entry, options)
    method = options && options[:unless_exist] ? :setnx : :set
    options[:node].send method, key, entry, options
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    false
  end

  def read_entry(key, options)
    entry = options[:node].get key, options
    if entry
      entry.is_a?(ActiveSupport::Cache::Entry) ? entry : ActiveSupport::Cache::Entry.new(entry)
    end
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    nil
  end

  def delete_entry(key, options)
    nodes = options[:node] ? [options[:node]] : @ring
    nodes.inject(false) do |result, node|
      begin
        node.del(key) || result
      rescue Errno::ECONNREFUSED, Redis::CannotConnectError
        result
      end
    end
  end
end
