# frozen_string_literal: true

module BattleCatsRolls
  module Provider
    module_function

    def extract_id_and_form_from_maanim_path path
      match = path.match(/(?<id>\d+)_(?<form>[fcs])02\.maanim\z/)
      id = match[:id].to_i.succ
      form_index = forms.index(match[:form])

      [id, form_index]
    end

    def forms
      %w[f c s]
    end
  end
end
