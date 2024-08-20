// Send a GET request to roxmartbox.xyz/tagHandler.php?pendingRequests=true to see if a user is waiting for a response to a friend request
// Send a request every 2 seconds, and if true is returned, check roblox friend requests at a max of every 10 seconds

let robloxCookie = `_|WARNING:-DO-NOT-SHARE-THIS.--Sharing-this-will-allow-someone-to-log-in-as-you-and-to-steal-your-ROBUX-and-items.|_2C2D17654C57493698522D30C6FD49B2B93C49E191585E6ED4C09F5B1A587ED0A7FE60B1C0716CCD3E7D9C2E46892BEA0C16863FF8ED79082235855D3A68DC72C8BB1258348F6594A7A367607D4819732AF521C9C244741DB7402699EB70540F290D6BBDF0AF0BC1B17727E55D86552E385A2EE585769EE54FB4BD429FF15C1399C9B2628FDF480681BC2F435623649034C46EF1C0746B273F3174AFCB3B920AD64DAF6A32D2EC9F381F29BF3555C0E2F4D478B0C0B5104B51C3383F64767F5D22522741FA52BF14F264590622AD78F2C91989231AAAF41635884299DAB18FFAE6331AA739A1FC686E9580B93FB5B95644B7D185AF9A5EE48A0776CD18E9B83CE10065B8B89F99544C61BDF3DD5BCB58F0D7E93175A990071EB218365EEA75AC4256580189AE2AD27DE6AC8D3C61213DE91CD54F8EE1E739E837CF06BB656E4B1EFEF036F92060087523FE43BA8E49FAC43A339F7AA2FE24456607A07FB12DA2329B641D17A5A375C792DEBE9C9AD58F51D8BDF53B101B5B5519AE647DEC67E07C1FF52B9DD4A075F6BD43EDB1809B11E65559370C570499B38C596DCAFE9AC7A3D63D92E2215F16FE0B4E93F9D79A3B59A2132A1CF0402A76D386B6D0971661A382F3C4A6853B95575C08444E9`
let xcsrfToken;
const fetch = require('node-fetch')

async function checkPendingRequests() {
    let response = await fetch('https://roxmartbot.xyz/tagHandler.php?pendingRequests=true')
    let data = await response.json()
    return data.data
}

async function checkFriendRequests() {
    let response = await fetch("https://friends.roblox.com/v1/my/friends/requests?limit=10&sortOrder=Desc", {
        headers: {
            "User-Agent": "Roblox/WinInet",
            'Cookie': `.ROBLOSECURITY=${robloxCookie}`,
        }
    })

    console.log(response.status, response.statusText, response)
    let responseData = await response.json();

    let data = responseData.data
    for (let i = 0; i < data.length; i++) {
        let friendRequest = data[i]
        let acceptRequest = await fetch(`https://friends.roblox.com/v1/users/${friendRequest.id}/accept-friend-request`, {
            headers: {
                'accept': "application/json",
                'content-type': "application/json",
                "User-Agent": "Roblox/WinInet",
                'Cookie': `.ROBLOSECURITY=${robloxCookie}`,
                "Referer": `https://www.roblox.com/users/${friendRequest.id}/profile`,
                "X-CSRF-TOKEN": xcsrfToken
            },
            method: 'POST'
        })

        if (acceptRequest.status == 200) {
            console.log(`Accepted friend request from ${friendRequest.name}`)
        } else {    
            console.log(`Failed to accept friend request from ${friendRequest.name}`)
        }
    }
}

async function getXcsrfToken() {
    let response = await fetch('https://friends.roblox.com/v1/users/1/accept-friend-request', {
        headers: {
            "User-Agent": "Roblox/WinInet",
            'Cookie': `.ROBLOSECURITY=${robloxCookie}`,
        },
        method: 'POST'
    })

    let token = response.headers.get("x-csrf-token");
    xcsrfToken = token
    return token
}

async function setPendingRequests() {
    let response = await fetch('https://roxmartbot.xyz/tagHandler.php?setPendingRequests=false&secretKey=CNUt2z2Ctouz7mGCEsZ0fdAD77BSk6RY')
    return response
}

async function main() {
    let pendingRequests = await checkPendingRequests()
    if (pendingRequests == "true") {
        console.log('Pending requests found! Checking roblox friend requests...')
        await checkFriendRequests()
        await setPendingRequests()
    }
}

getXcsrfToken()
setInterval(main, 3000) 
setInterval(getXcsrfToken, 300000)