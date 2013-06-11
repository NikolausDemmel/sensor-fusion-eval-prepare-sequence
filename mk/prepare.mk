SHELL:=/bin/bash

define variable-def
  ifndef $1
    $$(error $1 is undefined)
  # else
  #   $$(warning $1 is defined)
  endif
endef

$(eval $(call variable-def,START_TIME))
$(eval $(call variable-def,DURATION))

START_IMAGE:=$(START_TIME)
DURATION_IMAGE:=$(DURATION)
START_IMU:=$(shell bc <<< "$(START_TIME)-0.5")
DURATION_IMU:=$(shell bc <<< "$(DURATION)+1")
START_PS:=$(shell bc <<< "$(START_TIME)-1")
DURATION_PS:=$(shell bc <<< "$(DURATION)+2")


.PHONY: all build1 build2 clean killros
.SECONDARY:

all: build1 build2

build1: ps1_margin.txt ps1_margin.bag ps1.txt ps1.bag matched1.bag unmatched1.bag 
build2: ps2_margin.txt ps2_margin.bag ps2.txt ps2.bag matched2.bag unmatched2.bag 


clean:
	-rm  *.log *.txt tf*.bag ps*.bag *margin.bag *matched*.bag measurementinfocamera*.bag

killros:
	killall -2 record || true
	killall roslaunch || true
	killall roscore || true

tf%.bag: recorded.bag 
	[ 0 == `ps aux | grep "\(r\)osmaster" | wc -l` ] || (echo "Error: roscore is running!" && false) # hacky way to test if roscore is running
	roscore &
	sleep 3
	roslaunch ../config/handheld_with_phasespace$*.launch &
	sleep 1
	rosbag record -O $@ /tf &
	sleep 1
	roslaunch uvm_handheld_evaluation rosbag_play.launch bag:=recorded.bag topics:="/tf" rate:=5
	killall -2 record
	killall roslaunch
	killall roscore
	echo "Waiting for shutdown..."
	sleep 3
	echo "... complete."
	chmod a-w $@ # pretect from accidental deletion

ps%_margin.bag: ps%.bag
	rosrun uvm_handheld_evaluation rosbag_filter_subsequence.sh $< $@ $(START_PS) $(DURATION_PS) | tee $@.log

ps%_margin.txt: ps%_margin.bag
	rosrun rgbd_benchmark_tools extract_poses_from_bag.py -i $< -o $@ -t /ps

ps%.txt: tf%.bag
	rosrun rgbd_benchmark_tools extract_poses_from_bag.py -i $< -o $@ -t /tf -f /map -c /ps/camera_uvm_optical_frame | tee $@.log

ps%.bag: ps%.txt
	rosrun rgbd_benchmark_tools trajectory_txt2bag.py $< $@ -t /ps | tee $@.log

richimage_margin.bag: richimage.bag
	rosrun uvm_handheld_evaluation rosbag_filter_subsequence.sh richimage.bag richimage_margin.bag $(START_IMAGE) $(DURATION_IMAGE) | tee $@.log

imu_margin.bag: imu.bag
	rosrun uvm_handheld_evaluation rosbag_filter_subsequence.sh imu.bag imu_margin.bag $(START_IMU) $(DURATION_IMU) | tee $@.log

unmatched%.bag: richimage_margin.bag tf%.bag imu_margin.bag
	rosrun uvm_handheld_evaluation rosbag_merge.py $@ richimage_margin.bag tf$*.bag imu_margin.bag --verbose | tee $@.log

measurementinfocamera%.bag: unmatched%.bag
	rosrun vps_bag_tools bag_location_estimator -i $< -o $@ -d true -s ../config/c.xml -m ../config/m1.map | tee $@.log
	chmod a-w $@     # protect from accidental deletion
	chmod a-w $@.log # protect from accidental deletion

matched%.bag: measurementinfocamera%.bag imu_margin.bag tf%.bag
	rosrun uvm_handheld_evaluation rosbag_merge.py $@ imu_margin.bag tf$*.bag measurementinfocamera$*.bag -t "*camera_measurement_info *imu* *tf" --verbose | tee $@.log
