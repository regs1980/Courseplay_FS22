--- A fieldwork course for multiple vehicles
--- Previously, these courses were generated just like any other course, only with a different working width.
--- The working width was simply the working width of a single vehicle multiplied by the number of vehicles.
--- Then, when the vehicle was started and its position in the group was known, the course for that vehicle was
--- calculated by offsetting the course by the working width of the vehicle times the position in the group.
---
--- We could still follow that approach but a lot of information will be lost when the offset courses are generated.
--- At that point, most of the semantics of the original course are lost and makes it difficult to restore, things
--- like headland/center transitions, connecting paths, etc.
---
--- The above approach works well for the center, probably the only approach that works for any row pattern so this
--- course will generate the center with the multi-vehicle working width, and provides methods to calculate the
--- center part for the individual vehicles.
---
--- For the headlands though, it is better to generate them with the single working width and then pick and connect
--- the headlands for the individual vehicles.

---@class FieldworkCourseMultiVehicle : CourseGenerator.FieldworkCourse
local FieldworkCourseMultiVehicle = CpObject(CourseGenerator.FieldworkCourse)

---@param context CourseGenerator.FieldworkContext
function FieldworkCourseMultiVehicle:init(context)
    self.logger = Logger('FieldworkCourseMultiVehicle', Logger.level.debug)

    context:setCenterRowSpacing(context.workingWidth * context.nVehicles)
    context:setCenterRowWidthForAdjustment(context.workingWidth * context.nVehicles)

    if context.nHeadlands % context.nVehicles ~= 0 then
        local nHeadlands = context.nHeadlands
        if context.nHeadlands < context.nVehicles then
            context:setHeadlands(context.nVehicles)
        else
            context:setHeadlands(math.ceil(context.nHeadlands / context.nVehicles) * context.nVehicles)
        end
        self.logger:debug('Number of headlands (%d) adjusted to %d, be a multiple of the number of vehicles (%d)',
                nHeadlands, context.nHeadlands, context.nVehicles)
    end

    self:_setContext(context)
    self.headlandPaths = {}
    self.circledIslands = {}
    self.headlandCache = CourseGenerator.CacheMap()

    self.logger:debug('### Generating headlands around the field perimeter ###')
    self:generateHeadlands()
    self.logger:debug('### Setting up islands ###')
    self:setupAndSortIslands()

    if self.context.bypassIslands then
        self:routeHeadlandsAroundBigIslands()
    end

    if self.context.headlandFirst then
        -- connect the headlands first as the center needs to start where the headlands finish
        self.logger:debug('### Connecting headlands (%d) from the outside towards the inside ###', #self.headlands)
        for v = 1, self.context.nVehicles do
            -- create a headland path for each vehicle
            local headlands = {}
            for i = v, self.nHeadlands, self.context.nVehicles do
                table.insert(headlands, self.headlands[i])
            end
            self.headlandPaths[v] = CourseGenerator.HeadlandConnector.connectHeadlandsFromOutside(headlands,
                    self.context.startLocation, self.context:getHeadlandWorkingWidth(), self.context.turningRadius)
        end
        self:routeHeadlandsAroundSmallIslands()
        self.logger:debug('### Generating up/down rows ###')
        self:generateCenter()
    else
        -- here, make the center first as we want to start on the headlands where the center was finished
        self.logger:debug('### Generating up/down rows ###')
        local endOfLastRow = self:generateCenter()
        self.logger:debug('### Connecting headlands (%d) from the inside towards the outside ###', #self.headlands)
        for v = 1, self.context.nVehicles do
            -- create a headland path for each vehicle
            local headlands = {}
            for i = v, self.nHeadlands, self.context.nVehicles do
                table.insert(headlands, self.headlands[i])
            end
            self.headlandPaths[v] = CourseGenerator.HeadlandConnector.connectHeadlandsFromInside(headlands,
                    endOfLastRow, self.context:getHeadlandWorkingWidth(), self.context.turningRadius)
        end
        self:routeHeadlandsAroundSmallIslands()
    end

    if self.context.bypassIslands then
        self:bypassSmallIslandsInCenter()
        self.logger:debug('### Bypassing big islands in the center: create path around them ###')
        self:circleBigIslands()
    end
end

---@return Polyline
function FieldworkCourseMultiVehicle:getHeadlandPath(position)
    local headlandIx = self:positionToHeadlandIndex(position)
    self.logger:debug('Getting headland %d for position %d', headlandIx, position)
    return self.headlandPaths[headlandIx]
end

--- Returns a continuous Polyline covering the entire field. This is the
--- path a vehicle (the one defined in context.positionInGroup) would follow to complete work on the field.
--- The vertices of the path contain WaypointAttributes which provide additional navigation information
--- for the vehicle.
---@return Polyline
function FieldworkCourseMultiVehicle:getPath()
    if not self.path then
        self.path = Polyline()
        if self.context.headlandFirst then
            self.path:appendMany(self:getHeadlandPath(self.context.positionInGroup))
            self.path:appendMany(self:getCenterPath())
        else
            self.path:appendMany(self:getCenterPath())
            self.path:appendMany(self:getHeadlandPath(self.context.positionInGroup))
        end
        self.path:calculateProperties()
    end
    return self.path
end

--- Get the headlands for a given vehicle in the group.
---@param position number an integer defining the position of this vehicle within the group, negative numbers are to
--- the left, positives to the right. For example, a -2 means that this is the second vehicle to the left (and thus,
--- there are at least 4 vehicles in the group), a 0 means the vehicle in the middle (for groups with odd number of
--- vehicles)
---@return CourseGenerator.Headland[]
function FieldworkCourseMultiVehicle:positionToHeadlandIndex(position)
    if self.context.nVehicles % 2 == 0 then
        -- even number of vehicles, there is no 0 position
        if position < 0 then
            return position + self.context.nVehicles / 2 + 1
        else
            return position + self.context.nVehicles / 2
        end
    else
        return position + math.floor(self.context.nVehicles / 2) + 1
    end
end

---@class CourseGenerator.FieldworkCourseMultiVehicle : CourseGenerator.FieldworkCourse
CourseGenerator.FieldworkCourseMultiVehicle = FieldworkCourseMultiVehicle