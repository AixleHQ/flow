# frozen_string_literal: true

# A record's resource id lists (`tool_ids`, `base_repository_ids`, …), kept as
# its resource links. Each list is a virtual attribute that stays nil until it
# is assigned: an assigned list reads as assigned until the record saves and
# then replaces the links; any other list reads the links, which a deleted
# resource has already dropped out of.
module ResourceLists
  extend ActiveSupport::Concern

  included do
    class_attribute :resource_list_columns, instance_writer: false, default: {}.freeze
    class_attribute :resource_links_name, instance_writer: false
    after_save :link_resource_lists
  end

  class_methods do
    def resource_lists(links, prefix: nil)
      self.resource_links_name = links
      self.resource_list_columns = ResourceLink::COLUMNS.to_h { |list, column| [ "#{prefix}#{list}", column ] }.freeze
      resource_list_columns.each_key do |list|
        attribute list, :json
        define_method(list) { will_save_change_to_attribute?(list) ? super() : linked_ids(list) }
      end
    end
  end

  private

  # An assigned list its links do not already hold: what saving changes, and
  # what an ownership validation has to look at.
  def resource_list_changed?(list)
    will_save_change_to_attribute?(list) && ResourceLink.ids(self[list]) != linked_ids(list)
  end

  def linked_ids(list)
    return [] if new_record?

    public_send(resource_links_name).filter_map(&resource_list_columns.fetch(list.to_s))
  end

  def link_resource_lists
    assigned = resource_list_columns.select { |list, _| saved_change_to_attribute?(list) }
    return if assigned.empty?

    links = association(resource_links_name)
    assigned.each { |list, column| links.klass.replace!(self, column, self[list]) }
    links.reset
  end
end
