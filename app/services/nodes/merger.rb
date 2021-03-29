# frozen_string_literal: true

class Nodes::Merger
  def self.call(target_node, source_node)
    new(target_node, source_node).call
  end

  def initialize(target_node, source_node)
    @source_node = source_node
    @target_node = target_node
  end

  def call
    result = nil

    Node.transaction do
      move_descendents
      reset_counter_caches
      update_properties

      result = Node.destroy(source_node.id)
    end

    result || source_node
  end

  private

    attr_accessor :target_node, :source_node, :copied_attachments

    DESCENDENT_RELATIONSHIPS = {
      activities: :trackable_id,
      attachments: :record_id,
      children: :parent_id,
      evidence: :node_id,
      notes: :node_id
    }.freeze

    def move_descendents
      DESCENDENT_RELATIONSHIPS.each do |relation, column|
        source_node.send(relation).update_all(column => target_node.id)
      end
    end

    def reset_counter_caches
      Node.reset_counters target_node.id, :children_count
    end

    def update_properties
      source_node.properties.each do |key, value|
        case key.to_sym
        when :services
          value.each do |service|
            data = service.merge(source: :merge)
            target_node.set_service data
          end
        when :services_extras
          value.each do |protocol_port, extras|
            protocol, port = protocol_port.split('/')

            extras.each do |extra|
              data = {
                extra[:id] => extra[:output],
                source: extra[:source],
                port: port.to_i,
                protocol: protocol
              }

              target_node.set_service data
            end
          end
        else
          target_node.set_property key, value
        end
      end

      target_node.save
    end
end
