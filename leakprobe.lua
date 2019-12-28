-- Description: Check email/pw leaks via leakprobe.net API
-- Version: 0.1.0
-- Keyring-Access: leakprobe
-- Source: emails
-- License: GPL-3.0

function run(arg)
    API_URL = 'https://leakprobe.net/api/v1/api.php'

    local creds = keyring('leakprobe')[1]
    if not creds then
        return 'leakprobe api key is required, please login and visit https://leakprobe.net/documentation.php'
    end

    local session = http_mksession()
    local req = http_request(session, 'GET', API_URL, {
        query={
            apiKey=creds['secret_key'],
            dataFormat='JSON',
            email=arg['value'],
        }
    })

    local api_output = http_fetch_json(req)
    if last_err() then return end
    debug(api_output)

    for idx = 1, #api_output
    do
        local entry = api_output[idx]

        local breach_id = db_add('breach', {
            value=entry['location'],
        })
        if breach_id then
            local dbpw = entry['password']

            -- normalize missing fields
            if entry['salt'] == 'N/A' then
                entry['salt'] = ''
            end

            if (dbpw == nil or dbpw == '') then
                -- TODO implement hash only breaches datatype into sn0int
                dbpw = 'type:' ..entry['hashType'] ..', salt:' ..entry['salt'] ..', hash:' .. entry['hash']
            end

            db_add('breach-email', {
                breach_id=breach_id,
                email_id=arg['id'],
                password=dbpw
            })
        end
    end
end
