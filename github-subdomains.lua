-- Description: gathers subdomains via github
-- Version: 0.1.0
-- Keyring-Access: github
-- Source: domains
-- License: GPL-3.0

-- Author: ysf

-- blatently stolen from https://github.com/gwen001/github-search/blob/master/github-subdomains.py
-- creds to gwen001

-- Todos:
--      * loop through sorts + order
--      * add pagination
--      * IGNORECASE Regexes & Redirects in http_fetch

function to_raw_url(html_url)
    html_url = str_replace(html_url, 'https://github.com/', 'https://raw.githubusercontent.com/')
    return str_replace(html_url, '/blob/', '/')
end

function run(domain)
    API_URL = 'https://api.github.com/search/code'
    DOMAIN_REGEX = '(([0-9a-z_\\-\\.]+)\\.' .. str_replace(domain['value'], '.', '\\.') .. ')'

    -- url = 'https://api.github.com/search/code?per_page=100&s=' + sort + '&type=Code&o=' + order + '&q=' + search + '&page=' + str(page)

    local creds = keyring('github')[1]
    if not creds then
        return 'github api key missing, please login and visit https://github.com/settings/tokens - no permissions required.'
    end

    local session = http_mksession()
    local sort = 'indexed'
    local order = 'desc'
    local page = 1

    local req = http_request(session, 'GET', API_URL, {
        headers={
            authorization='token '..creds['access_key']
        },
        query={
            type='Code',
            q=domain['value'],
            per_page='100',
            s=sort,
            o=order,
            page=strval(page)
        }
    })

    resp = http_fetch_json(req)
    if last_err() then return end

    if not resp['items'] or #resp['items'] == 0 then
        return
    end

    used_urls = {}
    items = resp['items']
    found_subdomains = {}

    for i = 1, #items do
        item = items[i]
        raw_url = to_raw_url(item['html_url'])

        if not used_urls[raw_url] then
            req = http_request(session, 'GET', raw_url, {})
            resp = http_fetch(req)
            if last_err() then
                warn("skipping "..raw_url.." due to error: "..last_err())
                clear_err()
            else
                used_urls[raw_url] = 1
                blob = resp['text']
                subdomains = regex_find_all(DOMAIN_REGEX, blob)

                for j = 1, #subdomains do
                    candidate = subdomains[j][1]
                    if not found_subdomains[candidate] then
                        found_subdomains[candidate] = 1
                        db_add('subdomain', {
                            domain_id=domain['id'],
                            value=candidate
                        })
                    end
                end
            end
        end
    end
end
