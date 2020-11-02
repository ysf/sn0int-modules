-- Description: gathers subdomains via github
-- Version: 0.2.0
-- Keyring-Access: github
-- Source: domains
-- License: GPL-3.0

-- Author: ysf

-- blatently stolen from https://github.com/gwen001/github-search/blob/master/github-subdomains.py
-- creds to gwen001

-- Todos:
--      * IGNORECASE Regexes & Redirects in http_fetch

used_urls = {}
found_subdomains = {}
API_URL = 'https://api.github.com/search/code'
session = http_mksession()


function add_to_db(domain_id, subdomain)
    if found_subdomains[subdomain] then return end
    found_subdomains[subdomain] = 1
    db_add('subdomain', {domain_id=domain_id, value=subdomain})
end


function to_raw_url(html_url)
    html_url = str_replace(html_url, 'https://github.com/', 'https://raw.githubusercontent.com/')
    return str_replace(html_url, '/blob/', '/')
end


function fetch_user_content(raw_url)
    if used_urls[raw_url] then return end
    used_urls[raw_url] = 1

    debug("requesting raw user content "..raw_url)

    local req = http_request(session, 'GET', raw_url, {
        headers={authorization='token '..creds['access_key']},
        binary=true,
    })

    local resp = http_fetch(req)
    if last_err() then return end

    local body = utf8_decode(resp['binary'])
    if last_err() then
        clear_err()
        return nil
    end

    return body
end

function github_search(domain, sort, order, page)
    local req = http_request(session, 'GET', API_URL, {
        headers={authorization='token '..creds['access_key']},
        query={
            type='Code',
            q='"'..domain..'"',
            per_page='100',
            s=sort,
            o=order,
            page=strval(page)
        }
    })

    local resp = http_fetch(req)
    if last_err() then return end

    local data = json_decode(resp['text'])
    if last_err() then return end

    local reset_time = resp['headers']['x-ratelimit-reset']
    local remaining = resp['headers']['x-ratelimit-remaining']

    local now = time_unix()
    local reset_seconds = reset_time - now

    ratelimit_throttle('github-search', remaining - 1, reset_seconds*1000)

    info({reset_seconds=reset_seconds, reset_time=reset_time, remaining=remaining})

    return data['items']
end

function run(domain)
    local DOMAIN_REGEX = '(([0-9a-z_\\-\\.]+)\\.' .. str_replace(domain['value'], '.', '\\.') .. ')'

    creds = keyring('github')[1]
    if not creds then
        return 'github api key missing, please login and visit https://github.com/settings/tokens - no permissions required.'
    end

    local sort_order = {
        { sort='indexed', order='desc' },
        { sort='indexed', order='asc'  },
        { sort='',        order='desc' },
    }

    for o = 1, #sort_order do

        local page = 0
        local sort = sort_order[o]['sort']
        local order = sort_order[o]['order']

        while true do
            page = page + 1

            if page > 10 then
                break
            end

            info("requesting page "..page)

            local items = github_search(domain['value'], sort, order, page)

            if last_err() then return end

            if not items or #items == 0 then return end

            for i = 1, #items do
                local raw_url = to_raw_url(items[i]['html_url'])
                local body = fetch_user_content(raw_url)

                if last_err() then
                    warn("skipping "..raw_url.." due to error: "..last_err())
                    clear_err()

                elseif body then
                    local subdomains = regex_find_all(DOMAIN_REGEX, body)

                    for j = 1, #subdomains do
                        add_to_db(domain['id'], subdomains[j][1])
                    end

                    if last_err() then return end
                end
            end
        end
    end
end
