module Searchable
  include Patterns
  extend ActiveSupport::Concern

  included do
    include Elasticsearch::Model

    delegate :index_document, to: :__elasticsearch__
    delegate :update_document, to: :__elasticsearch__
    delegate :delete_document, to: :__elasticsearch__

    after_commit -> { delay.index_document  }, on: :create
    after_commit -> { delay.update_document }, on: :update
    after_commit -> { delay.delete_document }, on: :destroy

    def as_indexed_json(_options = {})
      most_recent_version = versions.most_recent
      {
        name: name,
        indexed: versions.any?(&:indexed?),
        info: most_recent_version.try(:description) || most_recent_version.try(:summary)
      }
    end

    settings number_of_shards: 1,
             number_of_replicas: 1,
             analysis: {
               analyzer: {
                 rubygem: {
                   type: 'pattern',
                   pattern: "[\s#{Regexp.escape(SPECIAL_CHARACTERS)}]+"
                 }
               }
             }

    mapping do
      indexes :name, analyzer: 'rubygem'
      indexes :indexed, type: 'boolean'
      indexes :info, analyzer: 'english'
    end

    def self.search(query)
      __elasticsearch__.search(
        query: {
          filtered: {
            query: {
              multi_match: {
                query: query,
                operator: 'and',
                fields: ['name^3', 'info']
              }
            },
            filter: {
              bool: {
                must: {
                  term: { indexed: true }
                }
              }
            }
          }
        },
        _source: %w(name info)
      )
    end
  end
end
