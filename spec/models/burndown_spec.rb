require 'spec_helper'

describe Burndown do

  context "relations" do
    it { should have_many(:iterations).order("number DESC").dependent(:destroy) }
    it { should have_many(:metrics).through(:iterations) }
  end

  context "attributes" do
    it { should allow_mass_assignment_of(:name) }
    it { should allow_mass_assignment_of(:pivotal_token) }
    it { should allow_mass_assignment_of(:pivotal_project_id) }
    it { should allow_mass_assignment_of(:campfire_subdomain) }
    it { should allow_mass_assignment_of(:campfire_token) }
    it { should allow_mass_assignment_of(:campfire_room_id) }
  end

  context "#campfire_enabled" do
    it "returns true when enabled" do
      burndown = FactoryGirl.create(:burndown_with_campfire)
      expect(burndown).to be_campfire_enabled
    end

    it "returns false when not enabled" do
      burndown = FactoryGirl.create(:burndown)
      expect(burndown).not_to be_campfire_enabled
    end
  end

  context "#current_iterations" do
    subject(:burndown) { FactoryGirl.create(:burndown_with_metrics, iteration_count: 3) }
    let!(:iteration)   { burndown.iterations.where(number: 3).first }

    it "returns the correct, current iteration" do
      expect(burndown.current_iteration).to eql(iteration)
    end
  end

  context "#previous_iterations" do
    subject { FactoryGirl.create(:burndown_with_metrics, iteration_count: 3) }

    it { expect(subject.iterations.count).to eql(3) }
    it { expect(subject.previous_iterations.count).to eql(2) }
    it { expect(subject.previous_iterations).to_not include(subject.current_iteration) }
  end

  context "import from Pivotal Tracker" do
    context "for a single burndown" do
      subject(:burndown) { FactoryGirl.create(
        :burndown,
        pivotal_project_id: 42,
        pivotal_token: "ABC")
      }

      let(:start_datetime)  { 1.week.ago }
      let(:finish_datetime) { 1.week.from_now }

      let(:pivotal_double) {
        double :pivotal_iteration,
          number: 123,
          pivotal_id: 42,
          start_at: start_datetime,
          finish_at: finish_datetime,
          utc_offset: 3600,
          unstarted: 1,
          started: 2,
          finished: 3,
          delivered: 5,
          accepted: 8,
          rejected: 13
      }

      before do
        subject.stub(:pivotal_iteration).and_return(pivotal_double)
      end

      context "Campfire notification" do
        before(:each) do
          burndown.update_attributes(
            campfire_subdomain: "subdomain",
            campfire_token: "secret-token",
            campfire_room_id: "4242")
          end

        it "calls Tinder with a notification after import" do
          expected = "A new burndown is available at http://focal.test/burndowns/#{burndown.id}"

          room = double(:tinder_room)
          room.should_receive(:speak).with(expected)

          campfire = double(:tinder_campfire)
          campfire.should_receive(:find_room_by_id).with(burndown.campfire_room_id).and_return(room)

          Tinder::Campfire.stub(:new).and_return(campfire)

          burndown.import
        end
      end

      context "force reload today" do
        it "updates todays data" do
          burndown.import

          new_double = double :pivotal_iteration,
            number: 123,
            pivotal_id: 42,
            start_at: start_datetime,
            finish_at: finish_datetime,
            utc_offset: 3600,
            unstarted: 99,
            started: 2,
            finished: 3,
            delivered: 5,
            accepted: 8,
            rejected: 13

          subject.stub(:pivotal_iteration).and_return(new_double)

          expect {
            burndown.force_update
          }.to change { Metric.last.unstarted }.from(1).to(99)
        end

        it "does not create a duplicate metric" do
          burndown.import

          new_double = double :pivotal_iteration,
            number: 123,
            pivotal_id: 42,
            start_at: start_datetime,
            finish_at: finish_datetime,
            utc_offset: 3600,
            unstarted: 99,
            started: 2,
            finished: 3,
            delivered: 5,
            accepted: 8,
            rejected: 13

          subject.stub(:pivotal_iteration).and_return(new_double)

          expect {
            burndown.force_update
          }.not_to change { Metric.count }
        end
      end

      context "imports fresh data" do
        it "update burndown utc_offset" do
          expect {
            burndown.import
          }.to change { burndown.utc_offset }.from(0).to(3600)
        end

        context "when the iteration was not yet recorded" do
          it "creates a new iteration " do
            expect {
              burndown.import
            }.to change { burndown.iterations.count }.by(1)
          end

          context "iteration data" do
            let(:iteration) { burndown.import ; Iteration.last }

            it { expect(iteration.number).to eql(123) }
            it { expect(iteration.pivotal_iteration_id).to eql(42) }
            it { expect(iteration.start_at).to eql(start_datetime) }
            it { expect(iteration.finish_at).to eql(finish_datetime) }
          end
        end

        context "when the iteration has been recorded" do
          before { burndown.import }

          it "does not create a new iteration" do
            expect {
              burndown.import
            }.to_not change { burndown.iterations.count }
          end
        end

        context "import metric data for tody" do
          it "creates a Metric" do
            expect {
              burndown.import
            }.to change { burndown.metrics.count }.by(1)
          end

          context "metric data" do
            let(:metric) { burndown.import ; Metric.last }

            it { expect(metric.iteration_id).to eql(Iteration.last.id) }
            it { expect(metric.captured_on).to eql(Time.now.utc.to_date) }

            it { expect(metric.unstarted).to eql(1) }
            it { expect(metric.started).to eql(2) }
            it { expect(metric.finished).to eql(3) }
            it { expect(metric.delivered).to eql(5) }
            it { expect(metric.accepted).to eql(8) }
            it { expect(metric.rejected).to eql(13) }
          end
        end
      end
    end

    context "for all the burndowns" do
      let(:one) { FactoryGirl.create(:burndown, pivotal_project_id: 42, pivotal_token: "ABC") }
      let(:two) { FactoryGirl.create(:burndown, pivotal_project_id: 88, pivotal_token: "XYZ") }

      before do
        Burndown.stub(:find_each).and_yield(one).and_yield(two)
      end

      it "for all burndowns" do
        one.should_receive(:import).once
        two.should_receive(:import).once

        Burndown.import_all
      end
    end
  end
end
