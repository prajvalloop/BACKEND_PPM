// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PPMMarket is Ownable {
    enum Status { Open, AwaitingResolution, Proposed,Resolved  }
    enum Side {None, Yes, No}
    struct Market{
        string question;
        uint256 createdAt;
        uint256 endTime;
        Status status;
        int8 outcome;     
        uint256 yesPool;
        uint256 noPool;
        address creator;
        string evidenceUri;
        uint256 proposedAt;
        int8 proposedOutcome;
        
        uint256 aiSupportStake;
        uint256 opposeStake;
        uint256 aiSupportVotes;
        uint256 opposeVotes;

    }
    uint256 public nextMarketId;
    uint256 public createFeeWei = 0.001 ether;
    uint256 challengeWindow=5 minutes;
    mapping(uint256 => Market) public markets;
    mapping(uint256 => uint256) public windowClosed;
    mapping(uint256 => mapping(address => uint256)) public yesStake;
    mapping(uint256 => mapping(address=> uint256)) public noStake;
    mapping(uint256 =>mapping(address => bool)) public claimed;
    mapping(uint256 =>mapping(address => bool)) public challengedclaimed;
    mapping(uint256 =>mapping(address => uint256)) public supportStake;
    mapping(uint256=>mapping(address=>uint256)) public opposeStake;
    event MarketClosed(uint256 indexed id);
    constructor() Ownable(msg.sender) {
        
    }
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    function getQuestion(uint256 id) public view returns (string memory){
        Market memory m=markets[id];
        return m.question;
    }
    function getCreator(uint256 id) public view returns (address){
        Market memory m=markets[id];
        return m.creator;
    }
    function createMarket(string calldata question,uint256 endTime) public payable returns (uint256){
        require(bytes(question).length>0);
        require(endTime>block.timestamp + 5 minutes);
        require(createFeeWei<=msg.value);
        uint256 id=nextMarketId++;
        markets[id]=Market({
            question:question,
            createdAt:uint256(block.timestamp),
            endTime:endTime,
            status:Status.Open,
            outcome:-1,
            yesPool:0,
            noPool:0,
            creator:msg.sender,
            evidenceUri:"",
            proposedAt:0,
            proposedOutcome:-1,
            aiSupportStake:0,
            opposeStake:0,
            aiSupportVotes:0,
            opposeVotes:0
            



        });
        return id;


    }
    function bet(uint256 id , bool betYes) public payable {
        Market storage m = markets[id];
        require(m.creator != address(0),"address cannot be null");
        require(m.status == Status.Open,"market not open");
        require(block.timestamp < m.endTime,"market is closed");
        
        if (betYes){
            m.yesPool+=msg.value;
            yesStake[id][msg.sender]+=msg.value;
        }
        else{
            m.noPool+=msg.value;
            noStake[id][msg.sender]+=msg.value;
        }

    }
    
    function claim(uint256 id) public  {
        require(markets[id].creator != address(0));
        require(markets[id].status==Status.Resolved);
        require(!claimed[id][msg.sender],"already claimed");
        Market storage m=markets[id];
        uint256 total=m.yesPool+m.noPool;
        uint256 toSend=0;
        if (m.outcome==1){
            uint256 w=yesStake[id][msg.sender];
            toSend=(w*total)/m.yesPool;

        }
        else{
            uint256 w=noStake[id][msg.sender];
            toSend=(w*total)/m.noPool;
        }
        claimed[id][msg.sender]=true;
        (bool ok ,)=msg.sender.call{value:toSend}("");
        require(ok);
    }
    function closeMarket(uint256 id) public{
        Market storage m=markets[id];
        require(markets[id].creator != address(0));
        require(markets[id].status==Status.Open);
        require(block.timestamp>=m.endTime);
        // m.outcome=1;
        m.status = Status.AwaitingResolution;
        emit MarketClosed(id);
    }
    function proposeAIOutcome(uint256 id,bool isYes,string calldata eventuri) public onlyOwner{
        Market storage m=markets[id];
        require(m.status == Status.AwaitingResolution);
        m.status=Status.Proposed;
        m.proposedAt=block.timestamp;
        windowClosed[id]=m.proposedAt+challengeWindow;
        if (isYes){
            m.proposedOutcome=1;
        }
        else{
            m.proposedOutcome=0;
        }
        m.evidenceUri=eventuri;
        m.aiSupportStake=0;
        m.opposeStake=0;
        m.aiSupportVotes=0;
        m.opposeVotes=0;
        
    }
    function stakeSupport(uint256 id) public payable{
        Market storage m=markets[id];
        require(m.status==Status.Proposed);
        require(block.timestamp <= m.proposedAt + challengeWindow, "window closed");
        require(msg.value>0);
        supportStake[id][msg.sender]+=msg.value;
        m.aiSupportStake+=msg.value;
        uint256 userStake = supportStake[id][msg.sender];
        uint256 votes = sqrt(userStake);
        m.aiSupportVotes += votes - sqrt(userStake - msg.value);


    }
    function stakeOppose(uint256 id) public payable {
        Market storage m = markets[id];
        require(m.status == Status.Proposed);
        require(block.timestamp <= m.proposedAt + challengeWindow, "window closed");
        require(msg.value > 0);

        opposeStake[id][msg.sender] += msg.value;
        m.opposeStake += msg.value;

        uint256 userStake = opposeStake[id][msg.sender];
        uint256 votes = sqrt(userStake);

        m.opposeVotes += votes - sqrt(userStake - msg.value);
        
    }
    function finalOutcome(uint256 id) public{
        Market storage m=markets[id];
        require(m.status==Status.Proposed);
        require(block.timestamp>m.proposedAt+challengeWindow);
        if(m.opposeVotes>m.aiSupportVotes){
            m.outcome=m.proposedOutcome==1? int8(0):int8(1);


        }
        else{
            m.outcome=m.proposedOutcome;
        }
        m.status = Status.Resolved;
    }
    function challengeRewards(uint256 id) public {
        Market storage m=markets[id];
        require(m.status==Status.Resolved);
        require(!challengedclaimed[id][msg.sender]);
        uint256 amountSend=0;
        if (m.aiSupportVotes>=m.opposeStake){
            require(m.aiSupportStake > 0, "no support stake");
            uint256 rewardPool=m.opposeStake;
            uint256 userStake=supportStake[id][msg.sender];
            require(userStake > 0, "not a winning staker");
            amountSend = (userStake * rewardPool) / m.aiSupportStake;
        }
        else{
            require(m.opposeStake > 0, "no oppose stake");

            uint256 rewardPool=m.aiSupportStake;
            uint256 userStake=opposeStake[id][msg.sender];
            require(userStake > 0, "not a winning staker");
            amountSend = (userStake * rewardPool) / m.opposeStake;

        }
        
        challengedclaimed[id][msg.sender]=true; 
        (bool ok, ) = msg.sender.call{value: amountSend}("");
        require(ok);


    }
    
    

    
   
}
