local wait, resume = coroutine.yield, coroutine.resume
local main_select_mode, main_local_vs_yourself, main_dumb_transition
local menu_reserved_keys = {}
local multi = false

function repeating_key(key)
  local key_time = keys[key]
  return this_frame_keys[key] or
    (key_time and key_time > 25 and key_time % 3 ~= 0)
end

function normal_key(key) return this_frame_keys[key] end
function menu_key_func(fixed, configurable, rept)
  local query = normal_key
  if rept then
    query = repeating_key
  end
  for i=1,#fixed do
    menu_reserved_keys[#menu_reserved_keys+1] = fixed[i]
  end
  return function(k)
    local res = false
    if multi then
      for i=1,#configurable do
        res = res or query(k[configurable[i]])
      end
    else
      for i=1,#fixed do
        res = res or query(fixed[i])
      end
      for i=1,#configurable do
        local keyname = k[configurable[i]]
        res = res or query(keyname) and
            not menu_reserved_keys[keyname]
      end
    end
    return res
  end
end

menu_up = menu_key_func({"up"}, {"up"}, true)
menu_down = menu_key_func({"down"}, {"down"}, true)
menu_left = menu_key_func({"left"}, {"left"}, true)
menu_right = menu_key_func({"right"}, {"right"}, true)
menu_enter = menu_key_func({"return","kenter","z"}, {"swap1"}, false)
menu_escape = menu_key_func({"escape","x"}, {"swap2"}, false)
menu_backspace = menu_key_func({"backspace"}, {"backspace"}, true)

local function clean_move_cursor(cursor, map, direction)
  local dx,dy = unpack(direction)
  local can_x,can_y = wrap(1, cursor[1]+dx, X), wrap(1, cursor[2]+dy, Y)
  while can_x ~= cursor[1] or can_y ~= cursor[2] do
    if map[can_x][can_y] and map[can_x][can_y] ~= map[cursor[1]][cursor[2]] then
      break
    end
    can_x,can_y = wrap(1, can_x+dx, X), wrap(1, can_y+dy, Y)
  end
  cursor[1],cursor[2] = can_x,can_y
  return cursor
end

local function clean_do_leave()
  my_win_count = 0
  op_win_count = 0
  write_char_sel_settings_to_file()
  return json_send({leave_room=true})
end

local function clean_draw_cursor(x,y,w,h,player_num,cursor_frame)
  local menu_width = Y*100
  local menu_height = X*80
  local spacing = 8
  local x_padding = math.floor((819-menu_width)/2)
  local y_padding = math.floor((612-menu_height)/2)
  set_color(unpack(colors.white))
  render_x = x_padding+(y-1)*100+spacing
  render_y = y_padding+(x-1)*100+spacing
  button_width = w*100-2*spacing
  button_height = h*100-2*spacing

  cur_img = IMG_char_sel_cursors[player_num][cursor_frame]
  cur_img_left = IMG_char_sel_cursor_halves.left[player_num][cursor_frame]
  cur_img_right = IMG_char_sel_cursor_halves.right[player_num][cursor_frame]
  local cur_img_w, cur_img_h = cur_img:getDimensions()
  local cursor_scale = (button_height+(spacing*2))/cur_img_h
  menu_drawq(cur_img, cur_img_left, render_x-spacing, render_y-spacing, 0, cursor_scale , cursor_scale)
  menu_drawq(cur_img, cur_img_right, render_x+button_width+spacing-cur_img_w*cursor_scale/2, render_y-spacing, 0, cursor_scale, cursor_scale)
end


local function clean_draw_button(x,y,w,h,str)
  local menu_width = Y*100
  local menu_height = X*80
  local spacing = 8
  local x_padding = math.floor((819-menu_width)/2)
  local y_padding = math.floor((612-menu_height)/2)
  set_color(unpack(colors.white))
  render_x = x_padding+(y-1)*100+spacing
  render_y = y_padding+(x-1)*100+spacing
  button_width = w*100-2*spacing
  button_height = h*100-2*spacing
  grectangle("line", render_x, render_y, button_width, button_height)

  --If char icon, draw it
  if IMG_character_icons[character_display_names_to_original_names[str]] then
    local orig_w, orig_h = IMG_character_icons[character_display_names_to_original_names[str]]:getDimensions()
    menu_draw(IMG_character_icons[character_display_names_to_original_names[str]], render_x, render_y, 0, button_width/orig_w, button_height/orig_h )
  end

  --
  local y_add,x_add = 10,30
  local pstr = str:gsub("^%l", string.upper)

  --Print button label
  gprint(pstr, render_x+6, render_y+y_add)
end

function main_charselect(mode)
  --Stop Music And set character select BG
  love.audio.stop()
  stop_the_music()
  bg = charselect

  --Set character select layout
  local map = {{"level", "level", "level", "level", "level", "level", "ready"},
           {"random", "windy", "sherbet", "thiana", "ruby", "lip", "elias"},
           {"flare", "neris", "seren", "phoenix", "dragon", "thanatos", "cordelia"},
           {"lakitu", "bumpty", "poochy", "wiggler", "froggy", "blargg", "lungefish"},
           {"raphael", "yoshi", "hookbill", "navalpiranha", "kamek", "bowser", "leave"}}

  --Init selected character/ready/level state
  local my_state = global_my_state or {character=config.character, level=config.level, cursor="level", ready=false}
  local op_state = global_op_state or {character="lip", level=5, cursor="level", ready=false}
  global_op_state = nil
  global_my_state = nil
  my_state.ready = false
  op_state.ready = false

  --Init cursors
  cursor,X,Y = {{1,1},{1,1}},5,7

  --Initiate keys
  local up,down,left,right = {-1,0}, {1,0}, {0,-1}, {0,1}

  --Initiate win counts
  my_win_count = my_win_count or 0
  op_win_count = op_win_count or 0

  --Save player's state?
  local prev_state = shallowcpy(my_state)

  --??? Something to do with the char select layout?
  local name_to_xy = {}
  print("character_select_mode = "..(character_select_mode or "nil"))
  print("map[1][1] = "..(map[1][1] or "nil"))
  for i=1,X do
    for j=1,Y do
      if map[i][j] then
        name_to_xy[map[i][j]] = {i,j}
      end
    end
  end

  local selected = {false, false}
  local active_str = {"level", "level"}
  local selectable = {level=true, ready=true}

  --Init variables for cursor blinking
  local cur_blink_frequency = 4
  local cur_pos_change_frequency = 8
  local player_num = 1
  local draw_my_cur_this_frame = false
  local draw_op_cur_this_frame = false
  local my_cursor_frame = 1
  local op_cursor_frame = 1

  --Start main loop
  menu_clock = 0
  while true do
    menu_clock = menu_clock + 1

    --Draw level+ready
    clean_draw_button(1,1,6,1,"level")
    clean_draw_button(1,7,1,1,"ready")

    --Check blink state for P1
    if my_state.ready then
      player_num = 1
      if (math.floor(menu_clock/cur_blink_frequency)+player_num)%2+1 == player_num then
        draw_my_cur_this_frame = true
        my_cursor_frame = 1
      else
        draw_my_cur_this_frame = false
      end
    else
      draw_my_cur_this_frame = true
      my_cursor_frame = (math.floor(menu_clock/cur_pos_change_frequency)+player_num)%2+1
    end
    --------
    --Check blink state for P2
    if(mode == "local" or mode == "net") then
      if op_state.ready then
        player_num = 1
        if (math.floor(menu_clock/cur_blink_frequency)+player_num)%2+1 == player_num then
          draw_op_cur_this_frame = true
          op_cursor_frame = 1
        else
          draw_op_cur_this_frame = false
        end
      else
        draw_op_cur_this_frame = true
        op_cursor_frame = (math.floor(menu_clock/cur_pos_change_frequency)+player_num)%2+1
      end
    else
      draw_op_cur_this_frame = false
    end
    --------

    --Example function to draw cursor
    --(draws over "level" button {1,1}, with width 6, player 1, frame 1)
    if draw_my_cur_this_frame then
      if my_state.cursor == "level" then
        clean_draw_cursor(1,1,6,1,1,my_cursor_frame)
      end
      if my_state.cursor == "ready" then
        clean_draw_cursor(1,7,1,1,1,my_cursor_frame)
      end
    end
    if draw_op_cur_this_frame then
      if op_state.cursor == "level" then
        clean_draw_cursor(1,1,6,1,2,op_cursor_frame)
      end
      if op_state.cursor == "ready" then
        clean_draw_cursor(1,7,1,1,2,op_cursor_frame)
      end
    end

    --Draw character names/buttons
    for i=2,X do
      for j=1,Y do

        --Draw char icon/button
        clean_draw_button(i,j,1,1,character_display_names[map[i][j]] or map[i][j])

        --If player cursor over it, then draw player cursor
        str = character_display_names[map[i][j]] or map[i][j]
        if my_state and my_state.cursor and (my_state.cursor == str or my_state.cursor == character_display_names_to_original_names[str]) then
          player_num = 1
          if draw_my_cur_this_frame then
            clean_draw_cursor(i,j,1,1,player_num,my_cursor_frame)
          end
        end
        if op_state and op_state.cursor and (op_state.cursor == str or op_state.cursor == character_display_names_to_original_names[str]) then
          player_num = 2
          if draw_op_cur_this_frame then
            clean_draw_cursor(i,j,1,1,player_num,op_cursor_frame)
          end
        end

        --End looping through char buttons
      end
    end


    --TODO: Write/Draw State Info
    local state = ""
    state = state..my_state.level.."  Char: "..character_display_names[my_state.character].."  Ready: "..tostring(my_state.ready or false).."\n"
    state = state..op_state.level.."  Char: "..character_display_names[op_state.character].."  Ready: "..tostring(op_state.ready or false)
    gprint(state, 50, 50)
    wait()

    --Input

    --If we aren't spectating, then control
    if not currently_spectating then

        local K = K
        localplayers = 1
        if mode == "local" then
          localplayers = 2
          multi = true
        end
        for i=1,localplayers do
          local k = K[i]
          --Move cursor P1
          if menu_up(K[i]) then
            if not selected[i] then cursor[i] = clean_move_cursor(cursor[i], map, up) end
          elseif menu_down(K[i]) then
            if not selected[i] then cursor[i] = clean_move_cursor(cursor[i], map, down) end
          elseif menu_left(K[i]) then
            if selected[i] and active_str[i] == "level" then
              if i == 1 then
                config.level = bound(1, config.level-1, 10)
                my_state.level = config.level
              else
                op_state.level = bound(1, op_state.level-1, 10)
              end
            end
            if not selected[i] then cursor[i] = clean_move_cursor(cursor[i], map, left) end
          elseif menu_right(K[i]) then
            if selected[i] and active_str[i] == "level" then
              if i == 1 then
                config.level = bound(1, config.level+1, 10)
                my_state.level = config.level
              else
                op_state.level = bound(1, op_state.level+1, 10)
              end
            end
            if not selected[i] then cursor[i] = clean_move_cursor(cursor[i], map, right) end

          --Selection
          elseif menu_enter(K[i]) then
            if selectable[active_str[i]] then
              selected[i] = not selected[i]
            elseif active_str[i] == "leave" then

              --Leave Online Match
              if character_select_mode == "2p_net_vs" then
                if not do_leave() then return false, nil, nil end
              else
                return false, nil, nil
              end

            --Different actions (random select, set ranked/character/ready)
            elseif active_str[i] == "random" then
              if i == 1 then
                config.character = uniformly(characters)
                my_state.character = config.character
              else
                op_state.character = uniformly(characters)
              end
            elseif active_str[i] == "match type desired" then
              config.ranked = not config.ranked
            else
              if i == 1 then
                config.character = active_str[i]
                my_state.character = config.character
              else
                op_state.character = active_str[i]
              end
              --When we select a character, move cursor to "ready"
              active_str[i] = "ready"
              cursor[i] = shallowcpy(name_to_xy["ready"])
            end

          --If hitting escape, then get ready to leave
          elseif menu_escape(K[i]) then
            if active_str[i] == "leave" then

              --Leave Online Match
              if character_select_mode == "2p_net_vs" then
                if not do_leave() then return false, nil, nil end
              else
                return false, nil, nil
              end

            end
            selected[i] = false
            cursor[i] = shallowcpy(name_to_xy["leave"])
          end

          --What are we hovering over?
          active_str[i] = map[cursor[i][1]][cursor[i][2]]

          if i == 1 then
            --Set state info
            my_state = {character=config.character, level=config.level, cursor=active_str[i], ranked=config.ranked,
                    ready=(selected[i] and active_str[i]=="ready")}
          else
            op_state.cursor = active_str[i]
            op_state.ready = (selected[i] and active_str[i]=="ready")
          end
        end

        --In net match, send our state info
        if character_select_mode == "2p_net_vs" and not content_equal(my_state, prev_state) and not currently_spectating then
          json_send({menu_state=my_state})
        end

        --Save state to previous so we can compare to see if things changed
        prev_state = my_state

    else -- (we are are spectating, so do spectator controls)
        if menu_escape(k) then
          do_leave()
          return false, nil, nil
        end
    end

    --Single player start game (1P vs self) move outside? expand to support other modes?
    if mode == "single" and my_state.ready then
      return true, my_state
    end
    if (mode == "local" or mode == "net") and my_state.ready and op_state.ready then
      return true, my_state, op_state
    end

  end
  return false, nil, nil
end