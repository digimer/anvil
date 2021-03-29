import { Grid, Switch } from '@material-ui/core';

import AllocationBar from './AllocationBar';
import { BodyText } from './Text';

const AnvilNode = ({
  node,
}: {
  node: Array<AnvilStatusNode & AnvilListItemNode>;
}): JSX.Element => {
  return (
    <>
      {node &&
        node.map(
          (n): JSX.Element => {
            return (
              <>
                <Grid container alignItems="center" justify="space-around">
                  <Grid item xs={6}>
                    <BodyText text={`Node: ${n.node_name}`} />
                  </Grid>
                  <Grid item xs={3}>
                    <Switch checked />
                  </Grid>
                  <Grid item xs={6}>
                    <BodyText text={`State: ${n.state}`} />
                  </Grid>
                  <Grid item xs={4}>
                    <BodyText text={n.state_message} />
                  </Grid>
                  <Grid item xs={10}>
                    <AllocationBar allocated={n.state_percent} />
                  </Grid>
                </Grid>
              </>
            );
          },
        )}
    </>
  );
};

export default AnvilNode;