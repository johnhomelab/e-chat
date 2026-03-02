class Api::V1::Accounts::OffersController < Api::V1::Accounts::BaseController
  before_action :set_offer, only: [:show, :update, :destroy]

  def index
    @offers = Current.account.offers
  end

  def show
    # @offer já definido pelo before_action
  end

  def create
    @offer = Current.account.offers.build(offer_params)
    @offer.save!
    render :create, status: :created
  end

  def update
    @offer.update!(offer_params)
    render :update
  end

  def destroy
    @offer.destroy!
    head :no_content
  end

  def search
    @offers = Current.account.offers.where('title ILIKE ?', "%#{params[:query]}%")
    render :index
  end

  private

  def set_offer
    @offer = Current.account.offers.find(params[:id])
  end

  def offer_params
    params.require(:offer).permit(:title, :value, :currency, :image, :type)
  end
end
