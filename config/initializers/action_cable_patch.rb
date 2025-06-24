# config/initializers/action_cable_patch.rb
module ActionCable
  module SubscriptionAdapter
    class Redis
      def listener_for(channel, &block)
        @listener.listen(channel, &block)
      end
    end
  end
end
