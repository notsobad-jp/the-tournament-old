class Users::RegistrationsController < Devise::RegistrationsController
  skip_before_action :require_no_authentication, :only => [ :new ]
  before_action :signout_guest, only: [:new]

  def new
    super
  end

  def create
    super
  end


  protected

    def signout_guest
      sign_out(current_user) if current_user && current_user.guest?
    end
end
