json.id resource.id
json.title resource.title
json.value resource.value
json.currency resource.currency
json.type resource.type
json.created_at resource.created_at
json.updated_at resource.updated_at
json.image_url resource.image.attached? ? url_for(resource.image) : nil
