-- Global variables
apikey = "489a2b671b597b3324e49564f92047cc"
title = ""
artist = ""
lyrics = ""
no_tracks = false
track_id = 0
track_ids = {}
track_names = {}
track_artists = {}
track_albums = {}

-- For dialog
dialog_is_opened = false
dlg = nil
tracks_list = nil
reload_button = nil
select_button = nil

function descriptor()
  return {
    title = "musiXmatch";
    version = "0.05";
    author = "aoeu, Scarabol";
    description = "<center><b>musiXmatch</b></center>"
    .. "Automatically fetch lyrics of songs from <a href='http://musiXmatch.com'>musiXmatch.com</a>";
    shortdesc = "Automatically fetch the lyrics of songs from musiXmatch.com";
    capabilities = { "menu"; "input-listener"--[[; "meta-listener"]] }
  }
end


function menu()
  return { "Get lyrics from musiXmatch", "About" }
end

-- Function triggered when the extension is activated
function activate()
	vlc.msg.dbg(_VERSION)
	vlc.msg.dbg("[musiXmatch] Activating")
  show_chooser()
	return true
end

-- Function triggered when the extension is deactivated
function deactivate()
	if dialog_is_opened then
		close()
	else
		dlg = nil
	end

	vlc.msg.dbg("[musiXmatch] Deactivated")
	return true
end

-- Function triggered when the dialog is closed
function close()
  tracks_list = nil
  reload_button = nil
  select_button = nil
  dialog_is_opened = false
	vlc.msg.dbg("[musiXmatch] Closing dialog")

	if dlg ~= nil then dlg:delete() end
	dlg = nil
	return true
end

function show_dialog_about()
	local data = descriptor()

  new_dialog("About")

	dlg:add_label("<center><b>" .. data.title .. " " .. data.version .. "</b></center>", 1, 1, 1, 1)
	dlg:add_html(data.description, 1, 2, 1, 1)

	return true
end

function new_dialog(title)
  close()
  dialog_is_opened = true
	dlg = vlc.dialog(title)
end

-- Function triggered when a element from the menu is selected
function trigger_menu(id)
	if id == 1 then
		return show_chooser()
	elseif id == 2 then
		return show_dialog_about()
	end

	vlc.msg.err("[musiXmatch] Invalid menu id: "..id)
	return false
end

function click_select()
  select_button:set_text("Getting lyrics...")
  if no_tracks then
    vlc.msg.dbg("[musiXmatch] No tracks")
    select_button:set_text("Select track")
    return false
  end
  local selection = tracks_list:get_selection()
  local index,name
  for index, name in pairs(selection) do
    if index ~= nil then
      track_id = index
      break
    end
  end
  if track_id == nil then
    vlc.msg.dbg("[musiXmatch] Couldn't get selection")
    select_button:set_text("Select track")
    return false
  end
  artist = track_artists[track_id]
  title = track_names[track_id]
  track_id = track_ids[track_id]
  if not get_lyrics() then
    vlc.msg.dbg("[musiXmatch] Couldn't get lyrics for track " .. track_id)
    select_button:set_text("Select track")
    return false
  end
  show_lyrics()
  return true
end

function reload()
  if tracks_list ~= nil then tracks_list:clear() end
  get_info()
  get_id()
  populate_list()
  return true
end

function show_chooser()
  get_info()
  get_id()
  if #track_ids == 1 then
    track_id = 1
    artist = track_artists[track_id]
    title = track_names[track_id]
    track_id = track_ids[track_id]
    if not get_lyrics() then
      vlc.msg.dbg("[musiXmatch] Couldn't get lyrics for track " .. track_id)
      return false
    end
    show_lyrics()
    return true
  end
  new_dialog("Lyrics Chooser")
  dlg:add_label("<center><b>Choose lyrics for " .. title .. " by " .. artist .. "</b></center>", 1, 1, 1, 1)
  dlg:add_label("<center>[title] by [artist] - [album] : [track id]</center>", 1, 2, 1, 1)
  tracks_list = dlg:add_list(1, 3, 1, 1)
  reload_button = dlg:add_button("Reload", reload, 1, 4, 1, 1)
  select_button = dlg:add_button("Select track", click_select, 1, 5, 1, 1)
  populate_list()
  return true
end

function populate_list()
  if not no_tracks then
    for i=1,#track_ids do
      if track_ids[i] ~= nil then
        local temp = ""
        if track_names[i] ~= nil then temp = temp .. track_names[i] end
        if track_artists[i] ~= nil then temp = temp .. " by " .. track_artists[i] end
        if track_albums[i] ~= nil then temp = temp .. " - " .. track_albums[i] end
        tracks_list:add_value(vlc.strings.resolve_xml_special_chars(temp) .. " : " .. track_ids[i], i)
      end
    end
  else
    tracks_list:add_value("Track not found", 1)
  end
  return true
end

function show_lyrics()
  new_dialog("Lyrics")
  dlg:add_label("<center><b>Lyrics for " .. title .. " by " .. artist .. "</b></center>", 1, 1, 1, 1)
  dlg:add_html("<center>" .. lyrics .. "</center>", 1, 2, 1, 1)
  return true
end

function get_info()
  vlc.msg.dbg("[musiXmatch] Getting song info")
  local item = vlc.input.item()
  if(item == nil) then return false end

  local metas = item:metas()
  if metas["title"] then title = metas["title"] else artist = "" end
  if metas["artist"] then artist = metas["artist"] else artist = "" end

  return true
end

function get_id()
  if((artist == nil or artist == "") and (title == nil or title == "")) then return false end

  local url = "http://api.musixmatch.com/ws/1.1/track.search?f_has_lyrics=1&format=xml&apikey=" .. apikey
  if(artist ~= nil and artist ~= "") then url = url .. "&q_artist=" .. artist end
  if(title ~= nil and title ~= "") then url = url .. "&q_track=" .. title end

  local stream = vlc.stream(url)
  if stream == nil then vlc.msg.err("[musiXmatch] musixmatch.com isn't reachable") return false end

  local reading = "this string left intentionally empty"
  local xmlpage = ""
  while(reading ~= nil and reading ~= "") do
    reading = stream:read(65653)
    if(reading) then
      xmlpage = xmlpage .. reading
    end
  end
  if xmlpage == "" then
    vlc.msg.err("[musiXmatch] couldn't get song ID")
    return false
  end

  local xmltext = string.gsub(xmlpage, "<%?xml version=\"1%.0\" encoding=\"utf%-8\"%?>", "")
  local xmldata = collect(xmltext)
  track_ids = {}
  track_names = {}
  track_artists = {}
  track_albums = {}
  local curtrack = 0

  for a,b in pairs(xmldata) do
    if type(b) == "table" then
      if b.label == "message" then
        for c,d in pairs(b) do
          if type(d) == "table" then
            if d.label == "body" then
              for e,f in pairs(d) do
                if type(f) == "table" then
                  if f.label == "track_list" then
                    for g,h in pairs(f) do
                      if type(h) == "table" then
                        if h.label == "track" then
                          curtrack = curtrack + 1
                          for i,j in pairs(h) do
                            if type(j) == "table" then
                              if j.label == "track_id" then
                                if j[1] ~= nil then
                                  track_ids[curtrack] = j[1]
                                else track_ids[curtrack] = "" end
                              elseif j.label == "artist_name" then
                                if j[1] ~= nil then
                                  track_artists[curtrack] = j[1]
                                else track_artists[curtrack] = "" end
                              elseif j.label == "album_name" then
                                if j[1] ~= nil then
                                  track_albums[curtrack] = j[1]
                                else track_albums[curtrack] = "" end
                              elseif j.label == "track_name" then
                                if j[1] ~= nil then
                                  track_names[curtrack] = j[1]
                                else track_names[curtrack] = j[1] end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  if curtrack == 0 then no_tracks = true else no_tracks = false end
    
end

function get_lyrics()
  if track_id == nil then vlc.msg.dbg("[musiXmatch] Unable to find track ID") return false end
  url = "http://api.musixmatch.com/ws/1.1/track.lyrics.get?format=xml&apikey=" .. apikey .. "&track_id=" .. track_id

  stream = vlc.stream(url)
  if stream == nil then
    vlc.msg.err("[musiXmatch] musixmatch.com isn't reachable")
    return false
  end

  reading = "this string left intentionally empty"
  xmlpage = ""
  while(reading ~= nil and reading ~= "") do
    reading = stream:read(65653)
    if(reading) then
      xmlpage = xmlpage .. reading
    end
  end
  if xmlpage == "" then
    vlc.msg.err("[musiXmatch] couldn't download lyrics")
    return false
  end

  local xmltext = string.gsub(xmlpage, "<%?xml version=\"1%.0\" encoding=\"utf%-8\"%?>", "")
  local xmldata = collect(xmltext)
  lyrics = ""

  for a,b in pairs(xmldata) do
    if type(b) == "table" then
      if b.label == "message" then
        for c,d in pairs(b) do
          if type(d) == "table" then
            if d.label == "body" then
              for e,f in pairs(d) do
                if type(f) == "table" then
                  if f.label == "lyrics" then
                    for g,h in pairs(f) do
                      if type(h) == "table" then
                        if h.label == "lyrics_body" then
                          if h[1] ~= nil then
                            lyrics = h[1]
                            break
                          else lyrics = "" end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  if lyrics == "" then
    vlc.msg.dbg("[musiXmatch] Lyrics not found")
    return false
  end

  lyrics = string.gsub(lyrics, "\n", "<br />")
  lyrics = string.gsub(lyrics, "... ******* This Lyrics is NOT for Commercial use *******", "")

  return true
end

-- XML Parsing
function parseargs(s)
	local arg = {}
	string.gsub(s, "(%w+)=([\"'])(.-)%2", function (w, _, a)
		arg[w] = a
	end)
	return arg
end

function collect(s)
	local stack = {}
	local top = {}
	table.insert(stack, top)
	local ni,c,label,xarg, empty
	local i, j = 1, 1
	while true do
		ni,j,c,label,xarg, empty = string.find(s, "<(%/?)([A-Za-z0-9_:]+)(.-)(%/?)>", i)
		if not ni then break end
		local text = string.sub(s, i, ni-1)
		if not string.find(text, "^%s*$") then
			table.insert(top, text)
		end
		if empty == "/" then -- empty element tag
			table.insert(top, {label=label, xarg=parseargs(xarg), empty=1})
		elseif c == "" then -- start tag
			top = {label=label, xarg=parseargs(xarg)}
			table.insert(stack, top) -- new level
		else -- end tag
			local toclose = table.remove(stack) -- remove top
			top = stack[#stack]
			if #stack < 1 then
				error("nothing to close with "..label)
			end
			if toclose.label ~= label then
				error("trying to close "..toclose.label.." with "..label)
			end
			table.insert(top, toclose)
		end
		i = j+1
	end
	local text = string.sub(s, i)
	if not string.find(text, "^%s*$") then
		table.insert(stack[#stack], text)
	end
	if #stack > 1 then
		error("unclosed "..stack[stack.n].label)
	end
	return stack[1]
end
