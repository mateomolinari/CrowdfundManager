//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract CrowdfundManager {
    address private admin;
    uint256 public campaignCounter;
    mapping(uint256 => Crowdfund) public campaigns;
    mapping(uint256 => uint256) public pledged;
    mapping(uint256 => mapping(address => uint256)) public pledgedBy;
    mapping(address => bool) private moderators;

    enum Status {
        INITIATED,
        ONGOING,
        SUCCESSFUL,
        FOR_WITHDRAWAL
    }

    struct Crowdfund {
        uint256 id;
        uint256 objective;
        uint256 startAt;
        uint256 endAt;
        address beneficiary;
        Status status;
    }

    modifier onlyModerator() {
        require(moderators[msg.sender], "not allowed to execute");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only available to admin");
        _;
    }

    event CrowdfundStart(uint256 indexed id);
    event Pledge(uint256 indexed id, uint256 value);
    event Unpledge(uint256 indexed id, uint256 value);
    event Successful(uint256 indexed id, uint256 value);
    event ForWithdrawal(uint256 indexed id);

    constructor(address[] memory _moderators) {
        admin = msg.sender;
        uint256 length = _moderators.length;
        for (uint256 i; i < length; ) {
            moderators[_moderators[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    function createCrowdfund(
        uint256 _objective,
        uint256 _startAt,
        address _beneficiary
    ) external onlyModerator {
        require(_objective != 0, "objective must be non zero");
        require(_startAt > block.timestamp, "invalid start time");
        require(_beneficiary != address(0), "invalid beneficiary");

        campaignCounter++;
        campaigns[campaignCounter] = Crowdfund({
            id: campaignCounter,
            objective: _objective,
            startAt: _startAt,
            endAt: _startAt + 2 weeks,
            beneficiary: _beneficiary,
            status: Status.INITIATED
        });
    }

    function cancelCrowdfund(uint256 _id) external onlyAdmin {
        require(_id <= campaignCounter, "campaign does not exist");
        Crowdfund storage campaign = campaigns[_id];
        if (campaign.status == Status.INITIATED) {
            delete campaigns[_id];
        } else if (campaign.status == Status.ONGOING) {
            campaign.status = Status.FOR_WITHDRAWAL;
        }
    }

    function startCrowdfund(uint256 _id) external onlyModerator {
        require(_id <= campaignCounter, "campaign does not exist");
        Crowdfund storage campaign = campaigns[_id];
        require(campaign.status == Status.INITIATED, "starting is not allowed");
        require(
            campaign.startAt <= block.timestamp &&
                campaign.endAt > block.timestamp,
            "inval_id time"
        );
        campaign.status = Status.ONGOING;

        emit CrowdfundStart(_id);
    }

    function pledge(uint256 _id) external payable {
        require(_id <= campaignCounter, "campaign does not exist");
        uint256 value = msg.value;
        require(value != 0, "value must be non zero");
        Crowdfund storage campaign = campaigns[_id];
        require(
            campaign.status == Status.ONGOING &&
                block.timestamp < campaign.endAt,
            "campaign is not active"
        );
        pledged[_id] += value;
        pledgedBy[_id][msg.sender] += value;

        emit Pledge(_id, value);
    }

    function removePledge(uint256 _id) external {
        require(_id <= campaignCounter, "campaign does not exist");
        address sender = msg.sender;
        uint256 pledgedByUser = pledgedBy[_id][sender];
        require(pledgedByUser != 0, "no amount pledged");
        pledgedBy[_id][sender] = 0;
        pledged[_id] -= pledgedByUser;
        (bool success, ) = sender.call{value: pledgedByUser}("");
        require(success, "failed to send ether");

        emit Unpledge(_id, pledgedByUser);
    }

    function terminateCrowdfund(uint256 _id) external {
        Crowdfund storage campaign = campaigns[_id];
        require(campaign.endAt <= block.timestamp, "campaign has not ended");
        uint256 amountPledged = pledged[_id];
        pledged[_id] = 0;
        if (campaign.objective >= amountPledged) {
            campaign.status = Status.SUCCESSFUL;
            (bool success, ) = campaign.beneficiary.call{value: amountPledged}(
                ""
            );
            require(success, "failed to send ether");
            emit Successful(_id, amountPledged);
        } else {
            campaign.status = Status.FOR_WITHDRAWAL;
            emit ForWithdrawal(_id);
        }
    }

    function withdraw(uint256 _id) external {
        require(_id <= campaignCounter, "campaign does not exist");
        Crowdfund storage campaign = campaigns[_id];
        require(
            campaign.status == Status.FOR_WITHDRAWAL,
            "withdrawal not available"
        );
        address sender = msg.sender;
        uint256 pledgedByUser = pledgedBy[_id][sender];
        pledgedBy[_id][sender] = 0;
        (bool success, ) = sender.call{value: pledgedByUser}("");
        require(success, "failed to send ether");
    }

    function manageModerators(address _moderator, bool _operation)
        external
        onlyAdmin
    {
        if (_operation) {
            moderators[_moderator] = true;
        } else {
            delete moderators[_moderator];
        }
    }
}
