class TournamentsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index, :show, :raw, :photos, :games, :players, :new, :create]
  load_and_authorize_resource
  before_action :authenticate_guest_user, only: [:edit, :update, :destroy, :upload, :edit_players, :update_players, :edit_games, :edit_game, :update_game]


  def index
    if params[:q]
      @title = "「#{params[:q]}」のトーナメント検索結果"
    elsif params[:tag]
      @title = "#{params[:tag]}のトーナメント一覧"
    else
      @title = "トーナメント一覧"
    end
    @page_title = (params[:page]) ? "#{@title} #{params[:page]}ページ目" : @title

    tournaments = Tournament.search_tournaments(params)
    per_page = 30
    @tournaments = tournaments.page(params[:page]).per(per_page)

    @page_start_count = params[:page] ? (params[:page].to_i - 1) * per_page + 1 : 1
    @page_end_count = @page_start_count + @tournaments.count - 1
  end


  def show
    redirect_to pretty_tournament_path(@tournament, @tournament.encoded_title), status: 301 if params[:title] != @tournament.encoded_title

    json = JSON.parse(@tournament.to_json)
    gon.push(json)
  end


  def raw
    json = JSON.parse(@tournament.to_json)
    gon.push(json)
    render layout: false
  end


  def embed
    json = JSON.parse(@tournament.to_json)
    gon.push(json)
    render layout: false
  end


  def upload
    json = @tournament.to_json
    File.write("tmp/#{@tournament.id}.json", json)
    uploader = TournamentUploader.new
    src = File.join(Rails.root, "/tmp/#{@tournament.id}.json")
    src_file = File.new(src)

    uploader.store!(src_file)
    render json: json
  end


  def new
    @tournament = Tournament.new

    # ゲストユーザーでログインしたまま来たら、tokenを変えるので一度ログアウトさせる
    sign_out(current_user) if current_user && current_user.guest?
    @token = SecureRandom.hex(8) if !current_user
  end


  def create
    @tournament = Tournament.new(tournament_params)

    # 未ログインの場合、ゲストユーザーとしてログインさせる
    if !current_user
      sign_in(User.find(1))
      session[:tournament_token] = tournament_params[:token]
    end

    @tournament.user = current_user

    respond_to do |format|
      if @tournament.save
        flash[:notice] = I18n.t('flash.tournament.create.success')
        format.html { redirect_to tournament_path(@tournament) }
        format.json { render action: 'show', status: :created, location: @tournament }
      else
        flash.now[:alert] = I18n.t('flash.tournament.create.failure')
        format.html { render action: 'new' }
        format.json { render json: @tournament.errors, status: :unprocessable_entity }
      end
    end
  end


  def edit
  end


  def update
    if @tournament.update(tournament_params)
      redirect_to tournament_edit_players_path(@tournament), notice: I18n.t('flash.tournament.update.success')
    else
      flash.now[:alert] = I18n.t('flash.tournament.update.failure')
      render 'tournaments/edit'
    end
  end


  def destroy
    @tournament.destroy
    respond_to do |format|
      format.html { redirect_to root_path, notice: 'トーナメントを削除しました' }
      format.json { head :no_content }
    end
  end


  def photos
    gon.album_id = @tournament.facebook_album_id
    gon.fb_token = ENV['FACEBOOK_APP_TOKEN'].sub('%7C', '|')
  end


  def players
    @players = @tournament.teams
  end


  def edit_players
    set_teams_text
  end


  def update_players
    teams = []
    # 通常入力
    if params[:input_type] == 'array'
      params[:tournament][:teams_array].each_with_index do |team, i|
        team_data = team['name'].present? ? { name: team['name'], flag: team['flag'].try(:downcase) } : nil
        teams << team_data
      end
    # まとめて入力
    elsif params[:input_type] == 'text'
      params[:tournament][:teams_text].lines.each_with_index do |line, i|
        team = line.chomp.split(",")
        team_data = (team[0].present?) ? {name: team[0], flag: team[1].try(:downcase)} : nil
        teams << team_data
      end
    end

    if @tournament.update({teams: teams})
      @tournament.update_bye_games
      redirect_to tournament_edit_players_path(@tournament), notice: I18n.t('flash.players.update.success')
    else
      set_teams_text
      @tournament.teams = @tournament.teams.in_groups_of(@tournament.size).first

      flash.now[:alert] = @tournament.errors.full_messages.first
      render 'tournaments/edit_players'
    end
  end


  def games
  end

  def edit_games
  end

  def edit_game
    @round_num = params[:round_num].to_i
    @game_num = params[:game_num].to_i
    @game = @tournament.results[@round_num-1][@game_num-1]

    @players = [
      @tournament.winner_team(@round_num, @game_num, 0),
      @tournament.winner_team(@round_num, @game_num, 1)
    ]

    @round_name = @tournament.round_name(round: @round_num)
    if @round_num == @tournament.round_num
      @game_name = (@game_num==1) ? '決勝戦' : '3位決定戦'
    else
      @game_name = "第#{@game_num}試合"
    end
  end

  def update_game
    @round_num = params[:round_num].to_i
    @game_num = params[:game_num].to_i

    game_params = {
      score: params[:game]['score'].map(&:to_i),
      winner: params[:game]['winner'].to_i,
      comment: params[:game]['comment'],
      finished: true
    }
    @tournament.results[@round_num-1][@game_num-1] = game_params

    tournament_params = { results: @tournament.results }
    tournament_params[:finished] = true if @round_num == @tournament.round_num && @game_num == 1

    if @tournament.update(tournament_params)
      redirect_to tournament_edit_games_path(@tournament), notice: I18n.t('flash.game.update.success')
    else
      flash.now[:alert] = I18n.t('flash.game.update.failure')
      render "tournaments/edit_game/#{@round_num}/#{@game_num}"
    end
  end


  private
    def tournament_params
      params.require(:tournament).permit(:id, :title, :user_id, :detail, :place, :url, :size, :consolation_round, :tag_list, :double_elimination, :scoreless, :facebook_album_id, :teams, :results, :token)
    end

    def set_teams_text
      @teams_text = ""
      @tournament.teams.each do |m|
        @teams_text += m['name'] if m
        @teams_text += ",#{m['flag']}" if m && m['flag'].present?
        @teams_text += "\r\n"
      end
    end

    #TODO:
    def authenticate_guest_user
      return if !current_user.guest?

      p session[:tournament_token]
      p @tournament.token
    end
end
