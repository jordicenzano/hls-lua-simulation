-- Set here the master playlist URL
local master_url = "http://playback-qa.a-live.io/16d23cf0ad4742dc80ec6277f2d3162c/us-west-2/BILLING02/014a1e197f474b799309445dc00a26f8/playlist_ssaiM.m3u8"

-- Set here the http[s] headers used to fetch the master URL
master_headers = {
  ["Accept"] = "*/*",
  ["Accept-Encoding"] = "gzip, deflate, sdch",
  ["Accept-Language"] = "en-US,en;q=0.8,es;q=0.6,ca;q=0.4",
  ["Cache-Control"] = "no-cache",
  ["Pragma"] = "no-cache",
  ["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"
}

-- Set here the http[s] headers used to fetch the master URL
local chunklist_headers = master_headers;

-- Set here the http[s] headers used to fetch the master URL
local chunk_headers = master_headers;

-- Session ID specific for Brightcove live SSAI, if you do not want ro use it put sid = "NONE"
local sid = ""

-- Time in miliseconds to substract to the time to wait to ask for the next chunklist
local wait_tolerance_ms = 0

-- Functions

-- Fetches the master playlst
local fetchMasterPlaylist = function(master_url, master_headers)
  local response = http.request({"GET", 
          master_url,
          headers = master_headers,
          response_body_bytes=100000})
  
  if response.status_code ~= 200 then
    log.error('Got error creating session - Fetching the master URL: Err: '..response.body)
    return nil
  end 

  return response.body
end

-- Randomly selects a chunklist from master playlist
local getChunklistUrlFromPlaylist = function(master_playlist)
  local ret = nil
  local arr = {}
  local i = 0
  
  local master_playlist_int = master_playlist.."\n"
  
  for line in master_playlist_int:gmatch"(.-)\n" do
    local pos = string.find(line,"#")
    if (pos == nil) then
      pos = 99
    end
        
    if (pos > 1 and string.len(line) > 0) then
      arr[i] = line
      i = i + 1
    end
  end
  
  
  if (i > 0) then
  	ret = arr[math.random(0, i-1)]
  end
  
  return ret
end

-- Transforms relative paths to absolute paths
local function absolute_path(base_path, relative_path)
    if string.sub(relative_path, 1, 1) == "/" then return relative_path end
    local path = string.gsub(base_path, "[^/]*$", "")
    path = path .. relative_path
    path = string.gsub(path, "([^/]*%./)", function (s)
        if s ~= "./" then return s else return "" end
    end)
    path = string.gsub(path, "/%.$", "/")
    local reduced
    while reduced ~= path do
        reduced = path
        path = string.gsub(reduced, "([^/]*/%.%./)", function (s)
            if s ~= "../../" then return "" else return s end
        end)
    end
    path = string.gsub(reduced, "([^/]*/%.%.)$", function (s)
        if s ~= "../.." then return "" else return s end
    end)
    return path
end

-- Get session ID from chunklist URL
local getSessionIdfromChunklistUrl = function(chunklist_abs_url)
  local prot, host ,jobid, region, billingid, profile, sid, fileAndQS = chunklist_abs_url:match("(.+)://(.+)/(.+)/(.+)/(.+)/(.+)/(.+)/(.+)")
	return sid
end

-- Fetches the rendition chunklist
local fetchChunklist = function(chunklist_url, chunklist_headers)
  local response = http.request({"GET", 
          chunklist_url,
          headers = chunklist_headers,
          response_body_bytes=1000000})

  if response.status_code ~= 200 then
    log.error('Got error fetching chunklist!: Err: '..response.body)
    return nil
  end 
  
  return response.body
end

-- Fetches one chunk
local fetchChunk = function(chunk_url, chunk_headers)
  local response = http.request({"GET", 
          chunk_url,
          headers = chunk_headers, 
    	  response_body_bytes=1000})

  if response.status_code ~= 200 then
    log.error('Got error fetching chunk!: Err: '..response.body)
    return nil
  end 
  
  return response.body, response.body_size
end

-- Gets the duration in secs from hls chunklist line
local getLastChunkDur = function(hls_line)
  return hls_line:match("#EXTINF:(%d+[\\.]?%d*)")
end

-- Gets the URL from hls chunklist line
local getLastChunkURL = function(hls_line)
  local ret = nil
  local badd = false
  
  if string.len(hls_line) <= 0 then
  	return nil
  end
  
  local pos = hls_line.find(hls_line,"#")
  
  if (pos == nil) then
    pos = 99
  end
  
  if pos > 1 then
  	ret = hls_line
  end
  
  return ret
end

-- Returns URL and duration from the last chunk in the chunklist
local getLastChunk = function(chunklist)
  local last_url = nil
  local last_dur = nil
    
  local chunklist = chunklist.."\n"
  
  for line in chunklist:gmatch"(.-)\n" do
    
    local last_dur_tmp = getLastChunkDur(line)
    if last_dur_tmp ~= nil then
      last_dur = last_dur_tmp
    else
      last_url_tmp = getLastChunkURL(line)
      if last_url_tmp ~= nil then
        last_url = last_url_tmp
      end
    end
    
  end
  
  return last_url, last_dur
end

-- CODE STARTS 
-- -----------------

-- read master playlist
master_playlist = fetchMasterPlaylist(master_url, master_headers)
if master_playlist == nil then
  log.error("Fetching master playlist")
  do return end
end

-- Peak one chunklist random
chunklist_url = getChunklistUrlFromPlaylist(master_playlist)
if chunklist_url == nil then
  log.error("Selecting rendition")
  do return end
end

chunklist_abs_url = absolute_path(master_url, chunklist_url)

-- Get session from master playlist (THIS LINE IS SPECIFIC FOR Brightcove live and SSAI)
if string.len(sid) <= 0 then
  sid = getSessionIdfromChunklistUrl(chunklist_abs_url)
  if sid == nil then
    log.error("Detecting the session ID")
    do return end
  end
end

log.debug("("..sid.."): Downloaded master playlist:\n"..master_playlist..". Rendition selected: " ..chunklist_url)

-- Fetch chunklist & chunks forever
while( true )
do
  start_time = os.time()

  -- Fetch selected chunklist
  chunklist = fetchChunklist(chunklist_abs_url, chunklist_headers)
  if chunklist == nil then
    log.error("("..sid.."): Fetching chuklist")
    do return end
  end

  log.debug("("..sid.."): Downloaded chunklist:\n"..chunklist)

  -- Get info from last chunk in the chunklist
  chunk_url, chunk_dur = getLastChunk(chunklist)
  if chunk_url == nil or chunk_dur ==nil then
    log.error("("..sid.."): Getting chunk info")
    do return end
  end
  
  chunk_abs_url = absolute_path(chunklist_abs_url, chunk_url)

  -- fetch chunk urls
  chunk, size = fetchChunk(chunk_abs_url, chunk_headers)
  if chunk == nil then
    log.error("("..sid.."): Downloading chunk: "..chunk_abs_url)
    do return end
  end

  log.debug("("..sid.."): Downloaded last chunk ("..chunk_dur.."s). Absolute URL:\n"..chunk_abs_url.."")
    
  -- Uncomment following line to do validations
  -- do return end
  
  -- Calculate the delay to fetch the next chunklist
  used_time_ms = (os.time() - start_time) * 1000
  wait_time_ms = (chunk_dur * 1000) - used_time_ms - wait_tolerance_ms
  
  if wait_time_ms > 0 then
    log.debug("("..sid.."): Waiting: "..wait_time_ms.."ms. Used time: "..used_time_ms.."ms")

    client.sleep(wait_time_ms, 1000)  
  else
    log.debug("("..sid.."): NO Waiting. Used time: "..used_time_ms)    
  end
   
end
