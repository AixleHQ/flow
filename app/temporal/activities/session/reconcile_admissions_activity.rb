# frozen_string_literal: true

module Activities
  module Session
    class ReconcileAdmissionsActivity < Base
      def run(_input = nil)
        SessionAdmissionReconciler.run
        { reconciled: true }
      end
    end
  end
end
