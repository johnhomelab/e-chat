json.array! @offers do |offer|
  json.partial! 'api/v1/models/offer', resource: offer
end
